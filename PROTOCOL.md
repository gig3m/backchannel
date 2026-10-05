# Plugin ↔ daemon protocol

`backchanneld` listens on `$XDG_RUNTIME_DIR/backchannel.sock` (mode 0600; connections
from other uids are refused via `SO_PEERCRED`). Messages are JSON objects, one per line.

## Requests and replies

```json
→ {"id": 7, "cmd": "send", "conv": "C0123", "text": "hello", "thread_ts": ""}
← {"id": 7, "ok": true, "result": {"ts": "1759680000.000100"}}
← {"id": 7, "ok": false, "error": "channel_not_found"}
```

Requests run concurrently; match replies by `id`.

| cmd | fields | result |
|---|---|---|
| `status` | | `State` |
| `setup` | `user_token` (xoxp-), `app_token` (xapp-) | `State`; tokens are checked with Slack, then saved |
| `logout` | | `State`; tokens deleted |
| `conversations` | | `[Conversation]` |
| `history` | `conv`, `before` (ts, optional), `limit` (≤200) | `{messages: [Message] oldest first, has_more}` |
| `replies` | `conv`, `ts` (thread root) | `{messages: [Message]}` root first |
| `send` | `conv`, `text`, `thread_ts` (optional) | `{ts}` |
| `mark` | `conv`, `ts` | `null`; marks read up to `ts` |
| `react` | `conv`, `ts`, `name` (emoji name), `on` (bool) | `null` |
| `file` | `file` (file id) | `{path}`; downloaded into the cache |
| `upload` | `conv`, `path` (absolute), `text`, `thread_ts` | `{id}` |
| `open_dm` | `user` | `Conversation` |

## Events

Events carry `event` and no `id`, and go to every connected client.

| event | fields |
|---|---|
| `state` | `State` |
| `conversations` | `{conversations: [Conversation]}`: the whole list |
| `conversation` | `Conversation`: one changed (unread counts, latest) |
| `conversations_changed` | membership changed; refetch |
| `message` | `conv`, `message`, `notify` (DM or mention from someone else), `direct`, `in_thread` |
| `message_changed` | `conv`, `message` |
| `message_deleted` | `conv`, `ts` |
| `reaction` | `conv`, `ts`, `name`, `emoji`, `user`, `me`, `added` |

## Shapes

```
State        { logged_in, connected, loading, team, team_id, url, user, user_id, error, version }
Conversation { id, name, kind: channel|private|dm|group, user_id, avatar, topic,
               unread, mentions, last_read, latest, open, ready }
Message      { ts, thread_ts, user, user_name, avatar, html, text, subtype, own, bot,
               mention, edited, reply_count, latest_reply, reactions: [Reaction], files: [File] }
Reaction     { name, emoji, count, me }
File         { id, name, mimetype, size, image, link }
```

`Message.html` is Slack's markup rendered to a small, escaped HTML subset (`b i s code pre
blockquote a br span.mention`); `Message.text` is the same as plain text.
