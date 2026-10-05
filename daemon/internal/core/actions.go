package core

import (
	"context"
	"errors"
	"strings"

	"github.com/slack-go/slack"
)

// edit replaces the text of one of the user's own messages. Slack refuses
// edits to anyone else's with cant_update_message.
func (d *Daemon) edit(ctx context.Context, conv, ts, text string) error {
	api, err := d.client()
	if err != nil {
		return err
	}
	if strings.TrimSpace(text) == "" {
		return errors.New("a message cannot be empty; delete it instead")
	}
	_, _, _, err = api.UpdateMessageContext(ctx, conv, ts, slack.MsgOptionText(escapeOutgoing(text), false), slack.MsgOptionLinkNames(true))
	return err
}

func (d *Daemon) deleteMessage(ctx context.Context, conv, ts string) error {
	api, err := d.client()
	if err != nil {
		return err
	}
	_, _, err = api.DeleteMessageContext(ctx, conv, ts)
	return err
}

// markUnread moves the read marker to just before ts, so that message and
// everything after it count as unread again. With no ts, the newest
// message is used.
func (d *Daemon) markUnread(ctx context.Context, conv, ts string) error {
	api, err := d.client()
	if err != nil {
		return err
	}
	if ts == "" {
		h, err := retry1(ctx, func() (*slack.GetConversationHistoryResponse, error) {
			return api.GetConversationHistoryContext(ctx, &slack.GetConversationHistoryParameters{ChannelID: conv, Limit: 1})
		})
		if err != nil {
			return err
		}
		if len(h.Messages) == 0 {
			return errors.New("nothing to mark unread")
		}
		ts = h.Messages[0].Timestamp
	}
	before := tsBefore(ts)
	if before == "" {
		return errors.New("bad ts")
	}
	if err := api.MarkConversationContext(ctx, conv, before); err != nil {
		return err
	}
	// Recount from the new marker.
	d.countUnread(ctx, api, conv, d.me())
	return nil
}

// tsBefore returns the timestamp one microsecond earlier:
// "1700000000.000100" → "1700000000.000099".
func tsBefore(ts string) string {
	sec, micro, ok := strings.Cut(ts, ".")
	if !ok || len(micro) != 6 || sec == "" {
		return ""
	}
	n := 0
	for _, c := range sec + micro {
		if c < '0' || c > '9' {
			return ""
		}
	}
	digits := []byte(sec + micro)
	// Subtract one with borrow.
	for i := len(digits) - 1; i >= 0; i-- {
		if digits[i] > '0' {
			digits[i]--
			break
		}
		digits[i] = '9'
		n++
	}
	if n == len(digits) {
		return ""
	}
	out := string(digits)
	return out[:len(sec)] + "." + out[len(sec):]
}

// closeConv hides a DM or group DM, as Slack's "Close conversation" does.
func (d *Daemon) closeConv(ctx context.Context, conv string) error {
	api, err := d.client()
	if err != nil {
		return err
	}
	c := d.conv(conv)
	if c == nil || (c.Kind != "dm" && c.Kind != "group") {
		return errors.New("only direct messages can be closed; leave a channel instead")
	}
	if _, _, err := api.CloseConversationContext(ctx, conv); err != nil {
		return err
	}
	d.updateConv(conv, func(c *Conversation) { c.Open = false })
	return nil
}

// leave takes the user out of a channel and drops it from the list.
func (d *Daemon) leave(ctx context.Context, conv string) error {
	api, err := d.client()
	if err != nil {
		return err
	}
	c := d.conv(conv)
	if c == nil || (c.Kind != "channel" && c.Kind != "private") {
		return errors.New("only channels can be left; close a direct message instead")
	}
	if _, err := api.LeaveConversationContext(ctx, conv); err != nil {
		return err
	}
	d.mu.Lock()
	delete(d.convs, conv)
	d.mu.Unlock()
	d.emit("conversations", map[string]any{"conversations": d.conversations()})
	return nil
}
