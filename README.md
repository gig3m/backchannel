# Backchannel

Slack in the [Omarchy](https://omarchy.org) bar and as a window. A shell plugin for the
interface, a small Go daemon for the Slack session, and a Slack app that you own.

- **Bar widget**: the count of conversations waiting on you; click for a popup with what
  needs attention and a composer, middle-click for the full window.
- **Window**: direct messages and channels, threads in a side pane, reactions, images,
  drag-and-drop uploads, `@`-completion, message search, and Ctrl+K to jump to a
  conversation, message anyone, or join a channel.
- **Notifications** through Omarchy's notifier, for DMs and mentions (or every channel
  message, if you like). Clicking one opens the conversation.
- **Follows your Omarchy theme**, colors and font, like the rest of the shell.

```
┌──────────────────────────┐  JSON lines   ┌───────────────────┐   HTTPS +     ┌───────┐
│ omarchy-shell            │  over a 0600  │ backchanneld      │  Socket Mode  │ Slack │
│  └ gig3m.backchannel     │◄─────────────►│  tokens, caches,  │◄─────────────►│       │
│    renders, forwards     │  Unix socket  │  live events      │  (your app)   │       │
└──────────────────────────┘               └───────────────────┘               └───────┘
```

The shell never sees a token. The daemon keeps both in `~/.local/state/backchanneld`
(mode 0600) and answers only processes running as you.

## Why your own Slack app

Slack hands out API tokens only to registered apps. Rather than ship one shared app
(which every workspace admin would have to approve, and which Slack's 2025 limits
throttle hard for apps distributed outside the Marketplace), each Backchannel user
creates a private app in their own workspace from the included
[manifest](slack-app-manifest.json). It talks only to your workspace, with your
permissions, under Slack's normal rate limits for internal apps. Setup takes about two
minutes and the plugin walks you through it.

If your workspace requires admin approval for new apps, your admin will be asked when
you install it.

## Install

**1. The daemon**

```bash
yay -S backchanneld-bin          # prebuilt
# or: yay -S backchanneld        # from source
systemctl --user enable --now backchanneld
```

**2. The plugin**

```bash
omarchy plugin add https://github.com/gig3m/backchannel --enable
```

**3. Sign in.** Click the Slack glyph in the bar. The plugin opens Slack's "create an
app" page with everything filled in; you generate an app token, install the app, and
paste the two tokens back.

To launch the window from the app launcher, copy
[`backchannel.desktop`](backchannel.desktop) to `~/.local/share/applications/`.

## Use

| | |
|---|---|
| Open the window | click the bar glyph (or middle-click, depending on the setting below), or `omarchy-shell shell summon gig3m.backchannel '{}'` |
| Bar menu | right-click the glyph, or `omarchy-shell gig3m.backchannel menu` |
| Choose what a click opens | right-click → Click opens, or the widget settings (popup by default; middle-click opens the other) |
| Toggle the popup | `omarchy-shell gig3m.backchannel toggle` (bind it in `~/.config/hypr/bindings.conf`) |
| Jump to a conversation | Ctrl+K in the window, or type in the popup |
| Message someone new, join a channel | Ctrl+K and type their name: people and public channels you're not in are listed after your conversations |
| Search messages | Ctrl+K, type, and pick "Messages with …" (or Ctrl+Shift+F); Slack's syntax works: `from:@name in:#channel before:2026-01-01`. Needs the `search:read` scope (see below) |
| Mention someone | type `@` and a few letters; Tab or Enter picks |
| Send / new line | Enter / Shift+Enter |
| Reply in a thread | hover a message, 󰍪 |
| View an image | click it: full size over the window, with Save, Copy, Open and Open in Slack (Esc closes); in the popup it opens in your image viewer |
| Download a file | click it: saved to `~/Downloads`, and the notification opens it |
| Send an image or file | Ctrl+V a clipboard image (screenshots included), 󰏢 for the file picker, or drop files on the conversation; they wait above the composer, and what you type becomes the caption. Enter sends, Esc clears |
| Edit your last message | Up in an empty composer (Esc cancels) |
| Right-click a conversation | mark read/unread, favourite, mute, copy link, open in Slack, close DM / leave channel |
| Right-click a message | react, reply in thread, copy text or link, open in Slack, mark unread from here, copy or save files; edit or delete your own |
| Status for scripts | `omarchy-shell gig3m.backchannel status` |
| Daemon logs | `journalctl --user -u backchanneld -f` |

An app made before search was added lacks the `search:read` scope. Add it at
<https://api.slack.com/apps> → your app → OAuth & Permissions → User Token Scopes, then
reinstall the app. If Slack shows a new User OAuth Token afterwards, sign out and paste it in.

## Not yet

Favourites and mute are kept by Backchannel, not Slack (the public API has neither), so
the official app won't see them.

Backchannel is young. Not there yet: custom emoji images, Slack's block layouts beyond their
text, multiple workspaces at once, and huddles (Slack has no public API for them).
Contributions welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Uninstall

```bash
omarchy plugin remove gig3m.backchannel
systemctl --user disable --now backchanneld
sudo pacman -R backchanneld-bin          # or backchanneld
rm -rf ~/.local/state/backchanneld ~/.cache/backchanneld
```

Then delete the app at <https://api.slack.com/apps> if you no longer want it.

## License

MIT. Backchannel is not affiliated with or endorsed by Slack Technologies.
