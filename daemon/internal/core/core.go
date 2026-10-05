// Package core owns the Slack session: tokens, the Web API client, the
// Socket Mode link, and the caches the plugin reads from.
package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/slack-go/slack"

	"github.com/gig3m/backchannel/daemon/internal/mrkdwn"
)

// Emitter sends an event to every connected plugin.
type Emitter func(event string, fields any)

type Daemon struct {
	emit    Emitter
	version string

	mu     sync.Mutex
	creds  *Credentials
	api    *slack.Client
	state  State
	convs  map[string]*Conversation
	users  map[string]*user
	cancel context.CancelFunc
}

type user struct {
	Name   string
	Avatar string
	Bot    bool
}

func New(emit Emitter, version string) *Daemon {
	return &Daemon{emit: emit, version: version, state: State{Version: version}}
}

// Start resumes the saved session, if there is one.
func (d *Daemon) Start() {
	c, err := loadCredentials()
	if err != nil {
		slog.Error("reading credentials", "err", err)
		d.setState(func(s *State) { s.Error = "could not read saved credentials: " + err.Error() })
		return
	}
	if c == nil {
		return
	}
	if err := d.connect(*c); err != nil {
		slog.Error("resuming session", "err", err)
	}
}

// Stop ends the session without forgetting it.
func (d *Daemon) Stop() {
	d.mu.Lock()
	if d.cancel != nil {
		d.cancel()
		d.cancel = nil
	}
	d.mu.Unlock()
}

func (d *Daemon) snapshot() State {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.state
}

func (d *Daemon) setState(f func(*State)) {
	d.mu.Lock()
	f(&d.state)
	s := d.state
	d.mu.Unlock()
	d.emit("state", s)
}

func (d *Daemon) client() (*slack.Client, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.api == nil {
		return nil, errors.New("not signed in")
	}
	return d.api, nil
}

func (d *Daemon) me() string {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.state.UserID
}

// connect checks the tokens against Slack, then starts the background
// work for the new session.
func (d *Daemon) connect(c Credentials) error {
	if err := c.Validate(); err != nil {
		return err
	}
	api := slack.New(c.UserToken, slack.OptionAppLevelToken(c.AppToken))
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	auth, err := api.AuthTestContext(ctx)
	cancel()
	if err != nil {
		d.setState(func(s *State) { s.Error = "Slack refused the user token: " + err.Error() })
		return fmt.Errorf("Slack refused the user token: %w", err)
	}

	d.Stop()
	sctx, scancel := context.WithCancel(context.Background())
	d.mu.Lock()
	d.creds = &c
	d.api = api
	d.cancel = scancel
	d.convs = map[string]*Conversation{}
	d.users = map[string]*user{}
	d.state = State{
		LoggedIn: true, Loading: true, Version: d.version,
		Team: auth.Team, TeamID: auth.TeamID, URL: auth.URL, User: auth.User, UserID: auth.UserID,
	}
	s := d.state
	d.mu.Unlock()
	d.emit("state", s)
	slog.Info("signed in", "team", auth.Team, "user", auth.User)

	go d.loadConversations(sctx, api)
	go d.runSocket(sctx, api)
	return nil
}

// ---------- requests ----------

func (d *Daemon) Handle(cmd string, raw json.RawMessage) (any, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	var f struct {
		UserToken string `json:"user_token"`
		AppToken  string `json:"app_token"`
		Conv      string `json:"conv"`
		TS        string `json:"ts"`
		ThreadTS  string `json:"thread_ts"`
		Before    string `json:"before"`
		Limit     int    `json:"limit"`
		Text      string `json:"text"`
		Name      string `json:"name"`
		On        bool   `json:"on"`
		File      string `json:"file"`
		Path      string `json:"path"`
		User      string `json:"user"`
	}
	if err := json.Unmarshal(raw, &f); err != nil {
		return nil, errors.New("bad request")
	}
	switch cmd {
	case "status":
		return d.snapshot(), nil
	case "setup":
		c := Credentials{UserToken: strings.TrimSpace(f.UserToken), AppToken: strings.TrimSpace(f.AppToken)}
		if err := d.connect(c); err != nil {
			return nil, err
		}
		if err := saveCredentials(c); err != nil {
			return nil, fmt.Errorf("signed in, but saving the tokens failed: %w", err)
		}
		return d.snapshot(), nil
	case "logout":
		d.Stop()
		if err := deleteCredentials(); err != nil {
			return nil, err
		}
		d.mu.Lock()
		d.api, d.creds, d.convs, d.users = nil, nil, nil, nil
		d.state = State{Version: d.version}
		s := d.state
		d.mu.Unlock()
		d.emit("state", s)
		return s, nil
	case "conversations":
		return d.conversations(), nil
	case "history":
		return d.history(ctx, f.Conv, f.Before, f.Limit)
	case "replies":
		return d.replies(ctx, f.Conv, f.TS)
	case "send":
		return d.send(ctx, f.Conv, f.Text, f.ThreadTS)
	case "mark":
		return nil, d.mark(ctx, f.Conv, f.TS)
	case "react":
		return nil, d.react(ctx, f.Conv, f.TS, f.Name, f.On)
	case "file":
		return d.fetchFile(ctx, f.File)
	case "upload":
		return d.upload(ctx, f.Conv, f.Path, f.Text, f.ThreadTS)
	case "open_dm":
		return d.openDM(ctx, f.User)
	}
	return nil, fmt.Errorf("unknown command %q", cmd)
}

// ---------- conversations ----------

func (d *Daemon) conversations() []Conversation {
	d.mu.Lock()
	defer d.mu.Unlock()
	out := make([]Conversation, 0, len(d.convs))
	for _, c := range d.convs {
		out = append(out, *c)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

func (d *Daemon) conv(id string) *Conversation {
	d.mu.Lock()
	defer d.mu.Unlock()
	if c, ok := d.convs[id]; ok {
		cp := *c
		return &cp
	}
	return nil
}

// updateConv changes one conversation and tells the plugin.
func (d *Daemon) updateConv(id string, f func(*Conversation)) {
	d.mu.Lock()
	c, ok := d.convs[id]
	if !ok {
		d.mu.Unlock()
		return
	}
	f(c)
	cp := *c
	d.mu.Unlock()
	d.emit("conversation", cp)
}

func kindOf(ch slack.Channel) string {
	switch {
	case ch.IsIM:
		return "dm"
	case ch.IsMpIM:
		return "group"
	case ch.IsPrivate:
		return "private"
	}
	return "channel"
}

// loadConversations lists what the user belongs to, then works out unread
// counts one conversation at a time, DMs first, inside Slack's rate limits.
func (d *Daemon) loadConversations(ctx context.Context, api *slack.Client) {
	me := d.me()
	var all []slack.Channel
	cursor := ""
	for {
		chs, next, err := retry(ctx, func() ([]slack.Channel, string, error) {
			return api.GetConversationsForUserContext(ctx, &slack.GetConversationsForUserParameters{
				UserID: me, Cursor: cursor, Limit: 200, ExcludeArchived: true,
				Types: []string{"public_channel", "private_channel", "mpim", "im"},
			})
		})
		if err != nil {
			if ctx.Err() == nil {
				slog.Error("listing conversations", "err", err)
				d.setState(func(s *State) { s.Error = "listing conversations: " + err.Error(); s.Loading = false })
			}
			return
		}
		all = append(all, chs...)
		if next == "" {
			break
		}
		cursor = next
	}

	d.mu.Lock()
	for _, ch := range all {
		c := &Conversation{ID: ch.ID, Name: ch.Name, Kind: kindOf(ch), Topic: ch.Topic.Value, UserID: ch.User, Open: !ch.IsIM}
		if c.Kind == "group" {
			c.Name = prettyGroupName(c.Name)
		}
		d.convs[ch.ID] = c
	}
	d.mu.Unlock()

	// DM names are the other person's name.
	for _, ch := range all {
		if ch.IsIM {
			u := d.user(ctx, ch.User)
			d.mu.Lock()
			if c := d.convs[ch.ID]; c != nil {
				c.Name, c.Avatar = u.Name, u.Avatar
			}
			d.mu.Unlock()
		}
	}
	d.emit("conversations", map[string]any{"conversations": d.conversations()})

	// Unread counts: DMs and group DMs first, they are what people answer.
	sort.SliceStable(all, func(i, j int) bool { return rank(all[i]) < rank(all[j]) })
	tick := time.NewTicker(1200 * time.Millisecond)
	defer tick.Stop()
	for _, ch := range all {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
		d.countUnread(ctx, api, ch.ID, me)
	}
	d.setState(func(s *State) { s.Loading = false })
}

func rank(ch slack.Channel) int {
	switch {
	case ch.IsIM:
		return 0
	case ch.IsMpIM:
		return 1
	case ch.IsPrivate:
		return 2
	}
	return 3
}

// "mpdm-alice--bob--carol-1" → "alice, bob, carol"
func prettyGroupName(n string) string {
	n = strings.TrimPrefix(n, "mpdm-")
	if i := strings.LastIndex(n, "-"); i > 0 {
		n = n[:i]
	}
	return strings.Join(strings.Split(n, "--"), ", ")
}

func (d *Daemon) countUnread(ctx context.Context, api *slack.Client, id, me string) {
	info, err := retry1(ctx, func() (*slack.Channel, error) {
		return api.GetConversationInfoContext(ctx, &slack.GetConversationInfoInput{ChannelID: id})
	})
	if err != nil {
		slog.Warn("conversation info", "conv", id, "err", err)
		return
	}
	lastRead := info.LastRead
	unread, mentions, latest := 0, 0, ""
	// last_read is zero for a conversation never opened; counting its whole
	// history would make every old channel look urgent.
	if lastRead != "" && !strings.HasPrefix(lastRead, "0000000000") {
		h, err := retry1(ctx, func() (*slack.GetConversationHistoryResponse, error) {
			return api.GetConversationHistoryContext(ctx, &slack.GetConversationHistoryParameters{ChannelID: id, Oldest: lastRead, Limit: 100})
		})
		if err == nil {
			for _, m := range h.Messages {
				if latest == "" || m.Timestamp > latest {
					latest = m.Timestamp
				}
				if m.User == me || hiddenSubtype(m.SubType) {
					continue
				}
				unread++
				if info.IsIM || info.IsMpIM || mrkdwn.Render(m.Text, me, nil).MentionsMe {
					mentions++
				}
			}
		}
	}
	if latest == "" && (info.IsIM || info.IsMpIM) {
		h, err := retry1(ctx, func() (*slack.GetConversationHistoryResponse, error) {
			return api.GetConversationHistoryContext(ctx, &slack.GetConversationHistoryParameters{ChannelID: id, Limit: 1})
		})
		if err == nil && len(h.Messages) > 0 {
			latest = h.Messages[0].Timestamp
		}
	}
	d.updateConv(id, func(c *Conversation) {
		c.LastRead, c.Unread, c.Mentions, c.Ready = lastRead, unread, mentions, true
		if latest > c.Latest {
			c.Latest = latest
		}
		if c.Kind == "dm" || c.Kind == "group" {
			// A DM stays in the sidebar while it is open in Slack or has
			// been active in the last two weeks.
			c.Open = info.IsOpen || unread > 0 || recent(c.Latest, 14*24*time.Hour)
		}
	})
}

func recent(ts string, within time.Duration) bool {
	t := tsTime(ts)
	return !t.IsZero() && time.Since(t) < within
}

func tsTime(ts string) time.Time {
	var sec int64
	for _, c := range ts {
		if c == '.' {
			break
		}
		if c < '0' || c > '9' {
			return time.Time{}
		}
		sec = sec*10 + int64(c-'0')
	}
	if sec == 0 {
		return time.Time{}
	}
	return time.Unix(sec, 0)
}

// Join and leave notices are not worth an unread badge.
func hiddenSubtype(st string) bool {
	switch st {
	case "channel_join", "channel_leave", "group_join", "group_leave", "channel_purpose", "channel_topic", "channel_name":
		return true
	}
	return false
}

// ---------- users ----------

// user returns a cached name and avatar, asking Slack the first time.
func (d *Daemon) user(ctx context.Context, id string) user {
	if id == "" {
		return user{Name: "unknown"}
	}
	d.mu.Lock()
	if d.users != nil {
		if u, ok := d.users[id]; ok {
			d.mu.Unlock()
			return *u
		}
	}
	api := d.api
	d.mu.Unlock()
	if api == nil {
		return user{Name: id}
	}
	info, err := retry1(ctx, func() (*slack.User, error) { return api.GetUserInfoContext(ctx, id) })
	if err != nil {
		return user{Name: id}
	}
	u := &user{Name: info.Profile.DisplayName, Avatar: info.Profile.Image72, Bot: info.IsBot}
	if u.Name == "" {
		u.Name = info.RealName
	}
	if u.Name == "" {
		u.Name = info.Name
	}
	d.mu.Lock()
	if d.users != nil {
		d.users[id] = u
	}
	d.mu.Unlock()
	return *u
}

// resolver names entities for mrkdwn.Render.
type resolver struct {
	d   *Daemon
	ctx context.Context
}

func (r resolver) UserName(id string) string { return r.d.user(r.ctx, id).Name }
func (r resolver) ChannelName(id string) string {
	if c := r.d.conv(id); c != nil {
		return c.Name
	}
	return ""
}

// ---------- messages ----------

func (d *Daemon) toMessage(ctx context.Context, m slack.Msg) Message {
	me := d.me()
	r := mrkdwn.Render(m.Text, me, resolver{d, ctx})
	out := Message{
		TS: m.Timestamp, ThreadTS: m.ThreadTimestamp, User: m.User, Subtype: m.SubType,
		HTML: r.HTML, Text: r.Plain, Mention: r.MentionsMe, Own: m.User != "" && m.User == me,
		Edited: m.Edited != nil, ReplyCount: m.ReplyCount, LatestReply: m.LatestReply,
		Reactions: []Reaction{}, Files: []File{},
	}
	if out.ThreadTS == out.TS {
		// A thread's root carries its own ts as thread_ts; the plugin only
		// needs thread_ts on replies.
		if out.ReplyCount == 0 {
			out.ThreadTS = ""
		}
	}
	switch {
	case m.BotID != "" && m.User == "":
		out.Bot = true
		out.UserName = m.Username
		if m.BotProfile != nil {
			if out.UserName == "" {
				out.UserName = m.BotProfile.Name
			}
			if m.BotProfile.Icons != nil {
				out.Avatar = m.BotProfile.Icons.Image48
			}
		}
		if m.Icons != nil && m.Icons.IconURL != "" {
			out.Avatar = m.Icons.IconURL
		}
		if out.UserName == "" {
			out.UserName = "bot"
		}
	default:
		u := d.user(ctx, m.User)
		out.UserName, out.Avatar, out.Bot = u.Name, u.Avatar, u.Bot
	}
	for _, re := range m.Reactions {
		mine := false
		for _, u := range re.Users {
			if u == me {
				mine = true
			}
		}
		out.Reactions = append(out.Reactions, Reaction{Name: re.Name, Emoji: mrkdwn.Emoji(re.Name), Count: re.Count, Me: mine})
	}
	for _, f := range m.Files {
		out.Files = append(out.Files, File{
			ID: f.ID, Name: firstNonEmpty(f.Title, f.Name), Mimetype: f.Mimetype, Size: f.Size,
			Image: strings.HasPrefix(f.Mimetype, "image/"), Link: f.Permalink,
		})
	}
	return out
}

func firstNonEmpty(s ...string) string {
	for _, v := range s {
		if v != "" {
			return v
		}
	}
	return ""
}

// history returns up to limit messages before `before` (newest when empty),
// oldest first, the order a chat view draws them.
func (d *Daemon) history(ctx context.Context, conv, before string, limit int) (any, error) {
	api, err := d.client()
	if err != nil {
		return nil, err
	}
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	h, err := retry1(ctx, func() (*slack.GetConversationHistoryResponse, error) {
		return api.GetConversationHistoryContext(ctx, &slack.GetConversationHistoryParameters{ChannelID: conv, Latest: before, Limit: limit})
	})
	if err != nil {
		return nil, err
	}
	msgs := make([]Message, 0, len(h.Messages))
	for i := len(h.Messages) - 1; i >= 0; i-- {
		msgs = append(msgs, d.toMessage(ctx, h.Messages[i].Msg))
	}
	if len(h.Messages) > 0 {
		newest := h.Messages[0].Timestamp
		d.updateConv(conv, func(c *Conversation) {
			if newest > c.Latest {
				c.Latest = newest
			}
		})
	}
	return map[string]any{"messages": msgs, "has_more": h.HasMore}, nil
}

func (d *Daemon) replies(ctx context.Context, conv, ts string) (any, error) {
	api, err := d.client()
	if err != nil {
		return nil, err
	}
	var all []slack.Message
	cursor := ""
	for {
		msgs, more, next, err := retry3(ctx, func() ([]slack.Message, bool, string, error) {
			return api.GetConversationRepliesContext(ctx, &slack.GetConversationRepliesParameters{ChannelID: conv, Timestamp: ts, Cursor: cursor, Limit: 200})
		})
		if err != nil {
			return nil, err
		}
		all = append(all, msgs...)
		if !more || next == "" || len(all) > 1000 {
			break
		}
		cursor = next
	}
	out := make([]Message, 0, len(all))
	for _, m := range all {
		out = append(out, d.toMessage(ctx, m.Msg))
	}
	return map[string]any{"messages": out}, nil
}

func (d *Daemon) send(ctx context.Context, conv, text, threadTS string) (any, error) {
	api, err := d.client()
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(text) == "" {
		return nil, errors.New("nothing to send")
	}
	opts := []slack.MsgOption{slack.MsgOptionText(escapeOutgoing(text), false), slack.MsgOptionLinkNames(true)}
	if threadTS != "" {
		opts = append(opts, slack.MsgOptionTS(threadTS))
	}
	_, ts, err := api.PostMessageContext(ctx, conv, opts...)
	if err != nil {
		return nil, err
	}
	return map[string]string{"ts": ts}, nil
}

// escapeOutgoing applies the three escapes Slack requires of message text.
func escapeOutgoing(s string) string {
	return strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;").Replace(s)
}

func (d *Daemon) mark(ctx context.Context, conv, ts string) error {
	api, err := d.client()
	if err != nil {
		return err
	}
	if ts == "" {
		return errors.New("ts is required")
	}
	if err := api.MarkConversationContext(ctx, conv, ts); err != nil {
		return err
	}
	d.updateConv(conv, func(c *Conversation) {
		if ts > c.LastRead {
			c.LastRead = ts
		}
		c.Unread, c.Mentions = 0, 0
	})
	return nil
}

func (d *Daemon) react(ctx context.Context, conv, ts, name string, on bool) error {
	api, err := d.client()
	if err != nil {
		return err
	}
	name = strings.Trim(name, ":")
	ref := slack.NewRefToMessage(conv, ts)
	if on {
		err = api.AddReactionContext(ctx, name, ref)
	} else {
		err = api.RemoveReactionContext(ctx, name, ref)
	}
	var se slack.SlackErrorResponse
	if errors.As(err, &se) && (se.Err == "already_reacted" || se.Err == "no_reaction") {
		return nil
	}
	return err
}

func (d *Daemon) openDM(ctx context.Context, userID string) (any, error) {
	api, err := d.client()
	if err != nil {
		return nil, err
	}
	ch, _, _, err := api.OpenConversationContext(ctx, &slack.OpenConversationParameters{Users: []string{userID}})
	if err != nil {
		return nil, err
	}
	u := d.user(ctx, userID)
	c := Conversation{ID: ch.ID, Name: u.Name, Avatar: u.Avatar, Kind: "dm", UserID: userID, Open: true, Ready: true}
	d.mu.Lock()
	if d.convs != nil {
		if old, ok := d.convs[ch.ID]; ok {
			old.Open = true
			c = *old
		} else {
			d.convs[ch.ID] = &c
		}
	}
	d.mu.Unlock()
	d.emit("conversation", c)
	return c, nil
}

// ---------- rate limits ----------

// retry repeats a Slack call that was rate limited, waiting as long as
// Slack asks, up to five times.
func retry[A, B any](ctx context.Context, f func() (A, B, error)) (A, B, error) {
	for i := 0; ; i++ {
		a, b, err := f()
		var rl *slack.RateLimitedError
		if i >= 5 || !errors.As(err, &rl) {
			return a, b, err
		}
		slog.Info("rate limited", "wait", rl.RetryAfter)
		select {
		case <-ctx.Done():
			return a, b, ctx.Err()
		case <-time.After(rl.RetryAfter + 250*time.Millisecond):
		}
	}
}

func retry1[A any](ctx context.Context, f func() (A, error)) (A, error) {
	a, _, err := retry(ctx, func() (A, struct{}, error) { a, err := f(); return a, struct{}{}, err })
	return a, err
}

func retry3[A, B, C any](ctx context.Context, f func() (A, B, C, error)) (A, B, C, error) {
	var c C
	a, b, err := retry(ctx, func() (A, B, error) {
		var a A
		var b B
		var err error
		a, b, c, err = f()
		return a, b, err
	})
	return a, b, c, err
}
