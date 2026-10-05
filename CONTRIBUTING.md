# Contributing

## Layout

- `manifest.json`, `*.qml`, `components/`: the Omarchy shell plugin (QML).
- `daemon/`: `backchanneld`, in Go. `internal/core` is the Slack session,
  `internal/ipc` the socket, `internal/mrkdwn` Slack markup → HTML.
- `PROTOCOL.md`: the wire format between the two. Change it with both sides.

## Develop

```bash
make test          # go vet + go test
make dev           # build the daemon to ~/.local/bin, install a user unit that runs it,
                   # and link this checkout into ~/.config/omarchy/plugins
make reload        # rebuild + restart the daemon; the shell reloads QML on save
qs log -p /usr/share/omarchy/shell | grep backchannel    # shell-side errors
journalctl --user -u backchanneld -f                     # daemon logs
```

Validate the plugin before a pull request: `omarchy plugin validate .`

## Style

Match what is there. QML: one service object owns all state; views never touch the
socket. Go: standard library first, errors returned with context, no global state.
