// backchanneld keeps a Slack session for the Backchannel Omarchy plugin and
// serves it over a Unix socket. See PROTOCOL.md for the wire format.
package main

import (
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"github.com/gig3m/backchannel/daemon/internal/core"
	"github.com/gig3m/backchannel/daemon/internal/ipc"
)

// Set at build time: -ldflags "-X main.version=1.2.3"
var version = "dev"

func main() {
	defaultSock := ""
	if rt := os.Getenv("XDG_RUNTIME_DIR"); rt != "" {
		defaultSock = filepath.Join(rt, "backchannel.sock")
	}
	sock := flag.String("socket", defaultSock, "path of the plugin socket")
	showVersion := flag.Bool("version", false, "print the version and exit")
	debug := flag.Bool("debug", false, "log debug detail")
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		return
	}
	level := slog.LevelInfo
	if *debug {
		level = slog.LevelDebug
	}
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level})))
	if *sock == "" {
		slog.Error("XDG_RUNTIME_DIR is not set; pass --socket")
		os.Exit(2)
	}

	var srv *ipc.Server
	d := core.New(func(event string, fields any) {
		if srv != nil {
			srv.Broadcast(event, fields)
		}
	}, version)

	srv, err := ipc.Listen(*sock, d.Handle)
	if err != nil {
		slog.Error("listen", "err", err)
		os.Exit(1)
	}
	slog.Info("backchanneld listening", "version", version, "socket", *sock)
	go d.Start()

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sig
		slog.Info("shutting down")
		d.Stop()
		srv.Close()
	}()
	if err := srv.Serve(); err != nil {
		slog.Error("serve", "err", err)
		os.Exit(1)
	}
}
