package core

import (
	"context"
	"errors"
	"net/url"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/slack-go/slack"
)

// The directory is everyone in the workspace and every public channel, for
// starting a DM, joining a channel and turning "@Name" into a mention.
// It is fetched on first use and kept for directoryTTL.

const directoryTTL = 30 * time.Minute

type Person struct {
	ID       string `json:"id"`
	Name     string `json:"name"`      // display name, else real name
	RealName string `json:"real_name"` // may equal Name
	Handle   string `json:"handle"`    // the legacy username
	Avatar   string `json:"avatar,omitempty"`
	Title    string `json:"title,omitempty"`
}

type ChannelInfo struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Topic   string `json:"topic,omitempty"`
	Members int    `json:"members"`
}

type directory struct {
	People   []Person
	Channels []ChannelInfo
	at       time.Time
	// mentions maps a lowercased name, real name or handle to a user ID,
	// leaving out any name two people share.
	mentions map[string]string
	longest  int // runes in the longest key
}

// directoryFor returns the cached directory, fetching it when missing or
// stale. Concurrent callers share one fetch.
func (d *Daemon) directoryFor(ctx context.Context) (*directory, error) {
	d.dirMu.Lock()
	defer d.dirMu.Unlock()
	d.mu.Lock()
	cur, api := d.dir, d.api
	d.mu.Unlock()
	if cur != nil && time.Since(cur.at) < directoryTTL {
		return cur, nil
	}
	if api == nil {
		return nil, errors.New("not signed in")
	}
	next, err := fetchDirectory(ctx, api, d.me())
	if err != nil {
		if cur != nil {
			return cur, nil // stale beats nothing
		}
		return nil, err
	}
	d.mu.Lock()
	if d.api == api {
		d.dir = next
		if d.users != nil {
			for _, p := range next.People {
				d.users[p.ID] = &user{Name: p.Name, Avatar: p.Avatar}
			}
		}
	}
	d.mu.Unlock()
	return next, nil
}

func fetchDirectory(ctx context.Context, api *slack.Client, me string) (*directory, error) {
	users, err := api.GetUsersContext(ctx, slack.GetUsersOptionLimit(200))
	if err != nil {
		return nil, err
	}
	dir := &directory{at: time.Now(), mentions: map[string]string{}}
	seen := map[string]string{}
	add := func(key, id string) {
		key = strings.ToLower(strings.TrimSpace(key))
		if key == "" {
			return
		}
		if other, ok := seen[key]; ok && other != id {
			seen[key] = "" // ambiguous: never guess
			return
		}
		seen[key] = id
	}
	for _, u := range users {
		if u.Deleted || u.IsBot || u.ID == "USLACKBOT" {
			continue
		}
		p := Person{
			ID: u.ID, Name: firstNonEmpty(u.Profile.DisplayName, u.RealName, u.Name),
			RealName: firstNonEmpty(u.RealName, u.Profile.RealName), Handle: u.Name,
			Avatar: u.Profile.Image72, Title: u.Profile.Title,
		}
		dir.People = append(dir.People, p)
		add(p.Name, p.ID)
		add(p.RealName, p.ID)
		add(p.Handle, p.ID)
	}
	for k, id := range seen {
		if id == "" {
			continue
		}
		dir.mentions[k] = id
		if n := utf8.RuneCountInString(k); n > dir.longest {
			dir.longest = n
		}
	}
	sort.Slice(dir.People, func(i, j int) bool { return strings.ToLower(dir.People[i].Name) < strings.ToLower(dir.People[j].Name) })

	cursor := ""
	for {
		chs, next, err := retry(ctx, func() ([]slack.Channel, string, error) {
			return api.GetConversationsContext(ctx, &slack.GetConversationsParameters{
				Cursor: cursor, Limit: 1000, ExcludeArchived: true, Types: []string{"public_channel"},
			})
		})
		if err != nil {
			return nil, err
		}
		for _, ch := range chs {
			dir.Channels = append(dir.Channels, ChannelInfo{ID: ch.ID, Name: ch.Name, Topic: firstNonEmpty(ch.Topic.Value, ch.Purpose.Value), Members: ch.NumMembers})
		}
		if next == "" {
			break
		}
		cursor = next
	}
	sort.Slice(dir.Channels, func(i, j int) bool { return dir.Channels[i].Name < dir.Channels[j].Name })
	return dir, nil
}

// directoryReply is what the plugin gets: people other than the user, and
// the public channels the user is not in yet.
func (d *Daemon) directoryReply(ctx context.Context) (any, error) {
	dir, err := d.directoryFor(ctx)
	if err != nil {
		return nil, err
	}
	me := d.me()
	people := make([]Person, 0, len(dir.People))
	for _, p := range dir.People {
		if p.ID != me {
			people = append(people, p)
		}
	}
	d.mu.Lock()
	channels := make([]ChannelInfo, 0, len(dir.Channels))
	for _, c := range dir.Channels {
		if _, member := d.convs[c.ID]; !member {
			channels = append(channels, c)
		}
	}
	d.mu.Unlock()
	return map[string]any{"people": people, "channels": channels}, nil
}

// join adds the user to a public channel and to the sidebar.
func (d *Daemon) join(ctx context.Context, conv string) (any, error) {
	api, err := d.client()
	if err != nil {
		return nil, err
	}
	ch, _, _, err := api.JoinConversationContext(ctx, conv)
	if err != nil {
		return nil, err
	}
	c := Conversation{ID: ch.ID, Name: ch.Name, Kind: kindOf(*ch), Topic: ch.Topic.Value, Open: true, Ready: true}
	d.mu.Lock()
	if d.convs != nil {
		if old, ok := d.convs[ch.ID]; ok {
			c = *old
		} else {
			d.convs[ch.ID] = &c
		}
	}
	d.mu.Unlock()
	d.emit("conversation", c)
	return c, nil
}

// ---------- search ----------

type SearchResult struct {
	Conv     string  `json:"conv"`
	ConvName string  `json:"conv_name"`
	Kind     string  `json:"kind"`
	ThreadTS string  `json:"thread_ts,omitempty"`
	Message  Message `json:"message"`
}

func (d *Daemon) search(ctx context.Context, query string, page int) (any, error) {
	api, err := d.client()
	if err != nil {
		return nil, err
	}
	query = strings.TrimSpace(query)
	if query == "" {
		return nil, errors.New("nothing to search for")
	}
	if page < 1 {
		page = 1
	}
	res, err := api.SearchMessagesContext(ctx, query, slack.SearchParameters{Sort: "timestamp", SortDirection: "desc", Count: 40, Page: page})
	var se slack.SlackErrorResponse
	if errors.As(err, &se) && se.Err == "missing_scope" {
		return nil, errors.New("searching needs the search:read scope: in your Slack app, add it under OAuth & Permissions → User Token Scopes, then reinstall the app")
	}
	if err != nil {
		return nil, err
	}
	out := make([]SearchResult, 0, len(res.Matches))
	for _, m := range res.Matches {
		r := SearchResult{Conv: m.Channel.ID, ConvName: m.Channel.Name, ThreadTS: threadOf(m.Permalink)}
		switch {
		case m.Channel.IsMPIM:
			r.Kind, r.ConvName = "group", prettyGroupName(m.Channel.Name)
		case strings.HasPrefix(m.Channel.ID, "D"):
			r.Kind = "dm"
		case m.Channel.IsPrivate:
			r.Kind = "private"
		default:
			r.Kind = "channel"
		}
		if c := d.conv(m.Channel.ID); c != nil {
			r.ConvName, r.Kind = c.Name, c.Kind
		}
		r.Message = d.toMessage(ctx, slack.Msg{Timestamp: m.Timestamp, User: m.User, Username: m.Username, Text: m.Text})
		r.Message.ThreadTS = r.ThreadTS
		out = append(out, r)
	}
	return map[string]any{"results": out, "total": res.Total, "page": res.Paging.Page, "pages": res.Paging.Pages}, nil
}

// threadOf reads thread_ts from a reply's permalink.
func threadOf(permalink string) string {
	u, err := url.Parse(permalink)
	if err != nil {
		return ""
	}
	return u.Query().Get("thread_ts")
}

// ---------- outgoing mentions ----------

// encodeOutgoing escapes text for Slack and turns "@Name" into a real
// mention, matching the longest display name, real name or handle that
// follows the @. Anything it cannot place unambiguously is left as typed
// (link_names still catches @here, @channel and #channel).
func (d *Daemon) encodeOutgoing(ctx context.Context, text string) string {
	if !strings.Contains(text, "@") {
		return escapeOutgoing(text)
	}
	dir, _ := d.directoryFor(ctx)
	return encodeMentions(text, dir)
}

func encodeMentions(text string, dir *directory) string {
	if dir == nil || len(dir.mentions) == 0 {
		return escapeOutgoing(text)
	}
	rs := []rune(text)
	var b strings.Builder
	start := 0
	for i := 0; i < len(rs); i++ {
		if rs[i] != '@' || (i > 0 && !boundary(rs[i-1])) {
			continue
		}
		id, n := "", 0
		for l := min(dir.longest, len(rs)-i-1); l > 0; l-- {
			if i+1+l < len(rs) && !boundary(rs[i+1+l]) {
				continue
			}
			if v, ok := dir.mentions[strings.ToLower(string(rs[i+1:i+1+l]))]; ok {
				id, n = v, l
				break
			}
		}
		if id == "" {
			continue
		}
		b.WriteString(escapeOutgoing(string(rs[start:i])))
		b.WriteString("<@" + id + ">")
		start = i + 1 + n
		i = start - 1
	}
	b.WriteString(escapeOutgoing(string(rs[start:])))
	return b.String()
}

// boundary is anything that can sit next to a mention: space and
// punctuation other than the characters names are made of.
func boundary(r rune) bool {
	if r == '.' || r == '-' || r == '_' || r == '\'' {
		return true
	}
	return !unicode.IsLetter(r) && !unicode.IsDigit(r)
}
