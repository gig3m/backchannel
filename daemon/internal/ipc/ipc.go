// Package ipc is the daemon's side of the plugin connection: JSON lines
// over a Unix socket that only the owning user can open.
//
// A request is {"id": 1, "cmd": "send", ...fields}. The reply carries the
// same id: {"id": 1, "ok": true, "result": …} or {"id": 1, "ok": false,
// "error": "…"}. Events have no id: {"event": "message", ...fields}, and go
// to every connected client.
package ipc

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"os"
	"sync"
	"syscall"
)

// Handler answers one request. fields is the whole request object.
type Handler func(cmd string, fields json.RawMessage) (any, error)

type Server struct {
	path    string
	handler Handler
	ln      *net.UnixListener

	mu      sync.Mutex
	clients map[*client]struct{}
}

type client struct {
	conn net.Conn
	mu   sync.Mutex // serialises writes
}

func (c *client) write(v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	_, err = c.conn.Write(append(b, '\n'))
	return err
}

// Listen creates the socket at path, replacing a stale one.
func Listen(path string, h Handler) (*Server, error) {
	if fi, err := os.Lstat(path); err == nil {
		if fi.Mode()&os.ModeSocket == 0 {
			return nil, fmt.Errorf("%s exists and is not a socket", path)
		}
		// A live daemon answers; a dead one leaves a file we can remove.
		if c, err := net.Dial("unix", path); err == nil {
			c.Close()
			return nil, fmt.Errorf("another daemon is listening on %s", path)
		}
		os.Remove(path)
	}
	old := syscall.Umask(0o177)
	ln, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	syscall.Umask(old)
	if err != nil {
		return nil, err
	}
	if err := os.Chmod(path, 0o600); err != nil {
		ln.Close()
		return nil, err
	}
	return &Server{path: path, handler: h, ln: ln, clients: map[*client]struct{}{}}, nil
}

// Serve accepts connections until Close.
func (s *Server) Serve() error {
	for {
		conn, err := s.ln.AcceptUnix()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return nil
			}
			return err
		}
		if !samePeer(conn) {
			slog.Warn("rejected a connection from another user")
			conn.Close()
			continue
		}
		c := &client{conn: conn}
		s.mu.Lock()
		s.clients[c] = struct{}{}
		s.mu.Unlock()
		go s.read(c)
	}
}

func (s *Server) Close() error {
	err := s.ln.Close()
	os.Remove(s.path)
	s.mu.Lock()
	for c := range s.clients {
		c.conn.Close()
	}
	s.mu.Unlock()
	return err
}

// Broadcast sends an event to every client. fields must marshal to an object.
func (s *Server) Broadcast(event string, fields any) {
	b, err := json.Marshal(fields)
	if err != nil {
		slog.Error("event marshal", "event", event, "err", err)
		return
	}
	m := map[string]json.RawMessage{}
	if len(b) > 0 && b[0] == '{' {
		json.Unmarshal(b, &m)
	}
	m["event"], _ = json.Marshal(event)
	s.mu.Lock()
	list := make([]*client, 0, len(s.clients))
	for c := range s.clients {
		list = append(list, c)
	}
	s.mu.Unlock()
	for _, c := range list {
		if err := c.write(m); err != nil {
			c.conn.Close()
		}
	}
}

// Clients is the number of connected plugins.
func (s *Server) Clients() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.clients)
}

func (s *Server) read(c *client) {
	defer func() {
		c.conn.Close()
		s.mu.Lock()
		delete(s.clients, c)
		s.mu.Unlock()
	}()
	sc := bufio.NewScanner(c.conn)
	sc.Buffer(make([]byte, 64*1024), 8*1024*1024)
	for sc.Scan() {
		line := append([]byte(nil), sc.Bytes()...)
		var head struct {
			ID  json.RawMessage `json:"id"`
			Cmd string          `json:"cmd"`
		}
		if err := json.Unmarshal(line, &head); err != nil || head.Cmd == "" {
			c.write(map[string]any{"id": head.ID, "ok": false, "error": "bad request"})
			continue
		}
		// Each request runs on its own goroutine, so a slow Slack call never
		// holds up the next one; replies are matched by id.
		go func() {
			res, err := s.handler(head.Cmd, line)
			if err != nil {
				c.write(map[string]any{"id": head.ID, "ok": false, "error": err.Error()})
				return
			}
			c.write(map[string]any{"id": head.ID, "ok": true, "result": res})
		}()
	}
}

// samePeer checks SO_PEERCRED: only our own uid may talk to the daemon.
func samePeer(conn *net.UnixConn) bool {
	raw, err := conn.SyscallConn()
	if err != nil {
		return false
	}
	var cred *syscall.Ucred
	var cerr error
	raw.Control(func(fd uintptr) {
		cred, cerr = syscall.GetsockoptUcred(int(fd), syscall.SOL_SOCKET, syscall.SO_PEERCRED)
	})
	return cerr == nil && cred != nil && int(cred.Uid) == os.Getuid()
}
