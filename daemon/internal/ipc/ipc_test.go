package ipc

import (
	"bufio"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRoundTrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "t.sock")
	s, err := Listen(path, func(cmd string, fields json.RawMessage) (any, error) {
		if cmd == "fail" {
			return nil, errors.New("nope")
		}
		var f struct{ N int }
		json.Unmarshal(fields, &f)
		return map[string]int{"double": f.N * 2}, nil
	})
	if err != nil {
		t.Fatal(err)
	}
	go s.Serve()
	defer s.Close()

	fi, _ := os.Stat(path)
	if fi.Mode().Perm() != 0o600 {
		t.Errorf("socket mode %v, want 0600", fi.Mode().Perm())
	}

	c, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	r := bufio.NewScanner(c)
	c.Write([]byte(`{"id":1,"cmd":"double","n":21}` + "\n"))
	read := func() map[string]any {
		c.SetReadDeadline(time.Now().Add(2 * time.Second))
		if !r.Scan() {
			t.Fatal("no reply")
		}
		var m map[string]any
		json.Unmarshal(r.Bytes(), &m)
		return m
	}
	m := read()
	if m["ok"] != true || m["result"].(map[string]any)["double"].(float64) != 42 {
		t.Errorf("reply %v", m)
	}
	c.Write([]byte(`{"id":2,"cmd":"fail"}` + "\n"))
	m = read()
	if m["ok"] != false || m["error"] != "nope" {
		t.Errorf("error reply %v", m)
	}
	for s.Clients() == 0 {
		time.Sleep(10 * time.Millisecond)
	}
	s.Broadcast("ping", map[string]string{"x": "y"})
	m = read()
	if m["event"] != "ping" || m["x"] != "y" {
		t.Errorf("event %v", m)
	}
}
