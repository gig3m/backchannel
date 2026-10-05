# Privacy

Backchannel has no server. It talks to Slack and nothing else.

- **Tokens** are stored by the daemon in `~/.local/state/backchanneld/credentials.json`,
  mode 0600. The shell plugin passes them to the daemon once, at setup, and never keeps
  them. Signing out deletes the file.
- **Messages** are held in memory while you read them and are not written to disk.
- **Images** you view are downloaded into `~/.cache/backchanneld/files` so they can be
  shown; delete that directory at any time.
- **Avatars** load from Slack's public avatar CDN.
- The daemon's socket accepts connections only from your own user.
- The Slack app is yours: it lives in your workspace, and you can revoke it at
  <https://api.slack.com/apps>.
