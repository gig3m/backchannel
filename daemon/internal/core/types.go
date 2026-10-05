package core

// The JSON shapes the plugin sees. Field names are the protocol; see
// PROTOCOL.md at the repository root.

type State struct {
	LoggedIn  bool   `json:"logged_in"`
	Connected bool   `json:"connected"` // the Socket Mode link is up
	Loading   bool   `json:"loading"`   // unread counts are still being fetched
	Team      string `json:"team,omitempty"`
	TeamID    string `json:"team_id,omitempty"`
	URL       string `json:"url,omitempty"`
	User      string `json:"user,omitempty"`
	UserID    string `json:"user_id,omitempty"`
	Error     string `json:"error,omitempty"`
	Version   string `json:"version"`
}

type Conversation struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Kind     string `json:"kind"` // channel, private, dm, group
	UserID   string `json:"user_id,omitempty"`
	Avatar   string `json:"avatar,omitempty"`
	Topic    string `json:"topic,omitempty"`
	Unread   int    `json:"unread"`
	Mentions int    `json:"mentions"`
	LastRead string `json:"last_read,omitempty"`
	Latest   string `json:"latest,omitempty"`
	Open     bool   `json:"open"`  // DMs: shown in the sidebar
	Ready    bool   `json:"ready"` // unread counts are known
}

type Reaction struct {
	Name  string `json:"name"`
	Emoji string `json:"emoji,omitempty"` // empty for custom emoji
	Count int    `json:"count"`
	Me    bool   `json:"me"`
}

type File struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Mimetype string `json:"mimetype"`
	Size     int    `json:"size"`
	Image    bool   `json:"image"`
	Link     string `json:"link,omitempty"` // permalink, opens in the browser
}

type Message struct {
	TS          string     `json:"ts"`
	ThreadTS    string     `json:"thread_ts,omitempty"`
	User        string     `json:"user,omitempty"`
	UserName    string     `json:"user_name"`
	Avatar      string     `json:"avatar,omitempty"`
	HTML        string     `json:"html"`
	Text        string     `json:"text"`
	Subtype     string     `json:"subtype,omitempty"`
	Own         bool       `json:"own"`
	Bot         bool       `json:"bot"`
	Mention     bool       `json:"mention"`
	Edited      bool       `json:"edited"`
	ReplyCount  int        `json:"reply_count,omitempty"`
	LatestReply string     `json:"latest_reply,omitempty"`
	Reactions   []Reaction `json:"reactions"`
	Files       []File     `json:"files"`
}
