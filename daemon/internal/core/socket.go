package core

import (
	"context"
	"log/slog"
	"time"

	"github.com/slack-go/slack"
	"github.com/slack-go/slack/slackevents"
	"github.com/slack-go/slack/socketmode"

	"github.com/gig3m/backchannel/daemon/internal/mrkdwn"
)

// runSocket keeps the Socket Mode link open for the life of the session
// and turns Slack's events into plugin events.
func (d *Daemon) runSocket(ctx context.Context, api *slack.Client) {
	for ctx.Err() == nil {
		sm := socketmode.New(api)
		done := make(chan error, 1)
		go func() { done <- sm.RunContext(ctx) }()
	loop:
		for {
			select {
			case <-ctx.Done():
				return
			case err := <-done:
				if ctx.Err() == nil {
					slog.Warn("socket mode ended", "err", err)
				}
				break loop
			case ev := <-sm.Events:
				d.socketEvent(ctx, sm, ev)
			}
		}
		d.setState(func(s *State) { s.Connected = false })
		select {
		case <-ctx.Done():
			return
		case <-time.After(5 * time.Second):
		}
	}
}

func (d *Daemon) socketEvent(ctx context.Context, sm *socketmode.Client, ev socketmode.Event) {
	switch ev.Type {
	case socketmode.EventTypeConnected:
		d.setState(func(s *State) { s.Connected = true; s.Error = "" })
	case socketmode.EventTypeConnecting, socketmode.EventTypeDisconnect:
		d.setState(func(s *State) { s.Connected = false })
	case socketmode.EventTypeInvalidAuth:
		d.setState(func(s *State) {
			s.Connected = false
			s.Error = "Slack refused the app token. Make a new one under Basic Information → App-Level Tokens, with connections:write."
		})
	case socketmode.EventTypeConnectionError:
		d.setState(func(s *State) { s.Connected = false })
	case socketmode.EventTypeEventsAPI:
		if ev.Request != nil {
			sm.Ack(*ev.Request)
		}
		api, ok := ev.Data.(slackevents.EventsAPIEvent)
		if !ok || api.Type != slackevents.CallbackEvent {
			return
		}
		d.callback(ctx, api.InnerEvent)
	default:
		if ev.Request != nil {
			sm.Ack(*ev.Request)
		}
	}
}

func (d *Daemon) callback(ctx context.Context, inner slackevents.EventsAPIInnerEvent) {
	switch e := inner.Data.(type) {
	case *slackevents.MessageEvent:
		d.onMessage(ctx, e)
	case *slackevents.ReactionAddedEvent:
		d.onReaction(e.Item.Channel, e.Item.Timestamp, e.Reaction, e.User, true)
	case *slackevents.ReactionRemovedEvent:
		d.onReaction(e.Item.Channel, e.Item.Timestamp, e.Reaction, e.User, false)
	case *slackevents.MemberJoinedChannelEvent, *slackevents.MemberLeftChannelEvent,
		*slackevents.ChannelCreatedEvent, *slackevents.ChannelRenameEvent, *slackevents.ChannelArchiveEvent:
		// Membership changed somewhere: let the plugin refetch.
		d.emit("conversations_changed", map[string]any{})
	}
}

func (d *Daemon) onMessage(ctx context.Context, e *slackevents.MessageEvent) {
	switch e.SubType {
	case "message_changed":
		if e.Message == nil {
			return
		}
		m := d.toMessage(ctx, *e.Message)
		d.emit("message_changed", map[string]any{"conv": e.Channel, "message": m})
		return
	case "message_deleted":
		d.emit("message_deleted", map[string]any{"conv": e.Channel, "ts": e.DeletedTimeStamp})
		return
	case "message_replied":
		// Thread metadata on the root; the reply itself arrives separately.
		if e.Message != nil {
			d.emit("message_changed", map[string]any{"conv": e.Channel, "message": d.toMessage(ctx, *e.Message)})
		}
		return
	}

	var raw slack.Msg
	if e.Message != nil {
		raw = *e.Message
	} else {
		raw = slack.Msg{User: e.User, Text: e.Text, Timestamp: e.TimeStamp, ThreadTimestamp: e.ThreadTimeStamp, SubType: e.SubType, BotID: e.BotID, Username: e.Username}
	}
	if raw.Timestamp == "" {
		raw.Timestamp = e.TimeStamp
	}
	if raw.ThreadTimestamp == "" {
		raw.ThreadTimestamp = e.ThreadTimeStamp
	}
	m := d.toMessage(ctx, raw)

	c := d.conv(e.Channel)
	if c == nil {
		// A conversation we have not seen: a new DM, or a channel just joined.
		d.emit("conversations_changed", map[string]any{})
	}
	direct := c != nil && (c.Kind == "dm" || c.Kind == "group") || e.ChannelType == "im" || e.ChannelType == "mpim"
	inThread := m.ThreadTS != "" && m.ThreadTS != m.TS && e.SubType != "thread_broadcast"
	fromOther := !m.Own && !hiddenSubtype(e.SubType)

	d.updateConv(e.Channel, func(c *Conversation) {
		if m.TS > c.Latest {
			c.Latest = m.TS
		}
		if m.Own {
			// Sending from anywhere reads the conversation up to here.
			c.LastRead, c.Unread, c.Mentions = m.TS, 0, 0
			return
		}
		if fromOther && !inThread {
			c.Unread++
			if direct || m.Mention {
				c.Mentions++
			}
			if c.Kind == "dm" || c.Kind == "group" {
				c.Open = true
			}
		}
	})

	notify := fromOther && (direct || m.Mention)
	d.emit("message", map[string]any{"conv": e.Channel, "message": m, "notify": notify, "direct": direct, "in_thread": inThread})
}

func (d *Daemon) onReaction(conv, ts, name, userID string, added bool) {
	if conv == "" || ts == "" {
		return
	}
	d.emit("reaction", map[string]any{
		"conv": conv, "ts": ts, "name": name, "emoji": mrkdwn.Emoji(name),
		"user": userID, "me": userID == d.me(), "added": added,
	})
}
