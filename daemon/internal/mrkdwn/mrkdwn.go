// Package mrkdwn turns Slack's message markup into the HTML subset a QML
// Text item renders as RichText, plus a plain-text form for notifications
// and previews.
//
// Slack text arrives with &, < and > already escaped; the only raw angle
// brackets are its own entities (<@U123>, <#C123|general>, <https://…|label>).
// Everything we emit is re-escaped, so nothing a sender types can become
// markup on the other side.
package mrkdwn

import (
	"html"
	"regexp"
	"strings"

	"github.com/kyokomi/emoji/v2"
)

// Resolver names the users and channels that entities refer to. Either
// method may return "" when the name is not known yet.
type Resolver interface {
	UserName(id string) string
	ChannelName(id string) string
}

// Result is one message rendered both ways.
type Result struct {
	HTML  string
	Plain string
	// MentionsMe is true when the text names the resolver's own user or
	// addresses the room (@here, @channel, @everyone).
	MentionsMe bool
}

var (
	entityRe = regexp.MustCompile(`<([^<>]+)>`)
	emojiRe  = regexp.MustCompile(`:([a-z0-9_+\-']+):`)
	emojiMap = emoji.CodeMap()
)

// Emoji returns the character for a Slack emoji name ("thumbsup",
// "+1"), or "" for a custom or unknown one.
func Emoji(name string) string {
	name = strings.Trim(name, ":")
	// Skin tones arrive as "wave::skin-tone-3"; drop the modifier.
	if i := strings.Index(name, "::"); i >= 0 {
		name = name[:i]
	}
	if s, ok := emojiMap[":"+name+":"]; ok {
		return strings.TrimSpace(s)
	}
	return ""
}

// Render converts Slack text. me is the reading user's id, for MentionsMe.
func Render(text, me string, r Resolver) Result {
	var out, plain strings.Builder
	res := Result{}
	// Fenced code first: nothing inside a fence is formatted.
	parts := strings.Split(text, "```")
	for i, part := range parts {
		if i%2 == 1 && i < len(parts)-1 {
			body := strings.Trim(part, "\n")
			h, p, m := entities(body, me, r, false)
			res.MentionsMe = res.MentionsMe || m
			out.WriteString(`<pre>` + h + `</pre>`)
			plain.WriteString(p)
			continue
		}
		if i%2 == 1 { // an unclosed fence: keep the backticks literally
			part = "```" + part
		}
		h, p, m := inline(part, me, r)
		res.MentionsMe = res.MentionsMe || m
		out.WriteString(h)
		plain.WriteString(p)
	}
	res.HTML = quotes(out.String())
	res.Plain = strings.TrimSpace(plain.String())
	return res
}

// inline handles `code` spans, then entities and emphasis in what is left.
func inline(s, me string, r Resolver) (string, string, bool) {
	var out, plain strings.Builder
	mentioned := false
	parts := strings.Split(s, "`")
	for i, part := range parts {
		if i%2 == 1 && i < len(parts)-1 && !strings.Contains(part, "\n") {
			h, p, m := entities(part, me, r, false)
			mentioned = mentioned || m
			out.WriteString(`<code>` + h + `</code>`)
			plain.WriteString(p)
			continue
		}
		if i%2 == 1 {
			part = "`" + part
		}
		h, p, m := entities(part, me, r, true)
		mentioned = mentioned || m
		out.WriteString(h)
		plain.WriteString(p)
	}
	return out.String(), plain.String(), mentioned
}

// Placeholders keep rendered entities out of the emphasis pass, so an
// underscore in a URL or a name is never read as italics.
const (
	phOpen  = ''
	phClose = ''
)

func entities(s, me string, r Resolver, format bool) (string, string, bool) {
	var held []string
	var plain strings.Builder
	mentioned := false
	last := 0
	var body strings.Builder
	for _, loc := range entityRe.FindAllStringSubmatchIndex(s, -1) {
		raw := s[loc[2]:loc[3]]
		text := s[last:loc[0]]
		body.WriteString(text)
		plain.WriteString(html.UnescapeString(text))
		h, p, m := entity(raw, me, r)
		mentioned = mentioned || m
		held = append(held, h)
		body.WriteRune(phOpen)
		body.WriteString(itoa(len(held) - 1))
		body.WriteRune(phClose)
		plain.WriteString(p)
		last = loc[1]
	}
	body.WriteString(s[last:])
	plain.WriteString(html.UnescapeString(s[last:]))

	// Re-escape: Slack's own escaping is undone and redone so a stray raw
	// character can never pass through as markup.
	h := html.EscapeString(html.UnescapeString(body.String()))
	if format {
		h = emphasis(h, "*", "b")
		h = emphasis(h, "_", "i")
		h = emphasis(h, "~", "s")
		h = emojiRe.ReplaceAllStringFunc(h, func(m string) string {
			if e := Emoji(m); e != "" {
				return e
			}
			return m
		})
	}
	h = strings.ReplaceAll(h, "\n", "<br>")
	// Put the entities back.
	h = restore(h, held)
	p := plain.String()
	if format {
		p = emojiRe.ReplaceAllStringFunc(p, func(m string) string {
			if e := Emoji(m); e != "" {
				return e
			}
			return m
		})
	}
	return h, p, mentioned
}

func restore(s string, held []string) string {
	var out strings.Builder
	for {
		i := strings.IndexRune(s, phOpen)
		if i < 0 {
			out.WriteString(s)
			return out.String()
		}
		j := strings.IndexRune(s[i:], phClose)
		if j < 0 {
			out.WriteString(s)
			return out.String()
		}
		out.WriteString(s[:i])
		n := atoi(s[i+len(string(phOpen)) : i+j])
		if n >= 0 && n < len(held) {
			out.WriteString(held[n])
		}
		s = s[i+j+len(string(phClose)):]
	}
}

// entity renders one <...> span.
func entity(raw, me string, r Resolver) (string, string, bool) {
	target, label, _ := strings.Cut(raw, "|")
	switch {
	case strings.HasPrefix(target, "@"):
		id := target[1:]
		name := label
		if name == "" && r != nil {
			name = r.UserName(id)
		}
		if name == "" {
			name = id
		}
		name = strings.TrimPrefix(name, "@")
		return `<span class="mention">@` + html.EscapeString(name) + `</span>`, "@" + name, id == me
	case strings.HasPrefix(target, "#"):
		id := target[1:]
		name := label
		if name == "" && r != nil {
			name = r.ChannelName(id)
		}
		if name == "" {
			name = id
		}
		return `<span class="mention">#` + html.EscapeString(name) + `</span>`, "#" + name, false
	case strings.HasPrefix(target, "!"):
		cmd := target[1:]
		switch {
		case cmd == "here" || cmd == "channel" || cmd == "everyone":
			return `<span class="mention">@` + cmd + `</span>`, "@" + cmd, true
		case strings.HasPrefix(cmd, "subteam^"):
			name := label
			if name == "" {
				name = "@group"
			}
			return `<span class="mention">` + html.EscapeString(name) + `</span>`, name, false
		default: // <!date^…|fallback> and the rest: the fallback text
			t := html.UnescapeString(label)
			return html.EscapeString(t), t, false
		}
	default:
		url := html.UnescapeString(target)
		if !safeURL(url) {
			t := html.UnescapeString(label)
			if t == "" {
				t = url
			}
			return html.EscapeString(t), t, false
		}
		text := html.UnescapeString(label)
		if text == "" {
			text = strings.TrimPrefix(url, "mailto:")
		}
		return `<a href="` + html.EscapeString(url) + `">` + html.EscapeString(text) + `</a>`, text, false
	}
}

func safeURL(u string) bool {
	l := strings.ToLower(u)
	return strings.HasPrefix(l, "https://") || strings.HasPrefix(l, "http://") || strings.HasPrefix(l, "mailto:")
}

// emphasis wraps marker-delimited runs in a tag, following Slack's rule
// that a marker opens after a boundary and closes before one.
func emphasis(s, marker, tag string) string {
	var out strings.Builder
	rs := []rune(s)
	m := []rune(marker)[0]
	i := 0
	for i < len(rs) {
		if rs[i] == m && opens(rs, i) {
			// find a closing marker on the same line
			for j := i + 1; j < len(rs) && rs[j] != '\n'; j++ {
				if rs[j] == m && j > i+1 && closes(rs, j) {
					out.WriteString("<" + tag + ">")
					out.WriteString(string(rs[i+1 : j]))
					out.WriteString("</" + tag + ">")
					i = j + 1
					goto next
				}
			}
		}
		out.WriteRune(rs[i])
		i++
	next:
	}
	return out.String()
}

func boundary(r rune) bool {
	return r == ' ' || r == '\n' || r == '\t' || strings.ContainsRune("()[]{}.,;:!?\"'*_~-/>", r) || r == phOpen || r == phClose
}

func opens(rs []rune, i int) bool {
	if i+1 >= len(rs) || rs[i+1] == ' ' || rs[i+1] == '\n' {
		return false
	}
	return i == 0 || boundary(rs[i-1]) || (i >= 4 && string(rs[i-4:i]) == "&gt;")
}

func closes(rs []rune, j int) bool {
	if rs[j-1] == ' ' {
		return false
	}
	return j == len(rs)-1 || boundary(rs[j+1]) || rs[j+1] == '&' || rs[j+1] == '<'
}

// quotes turns lines starting with "&gt; " into an indented, muted block.
func quotes(h string) string {
	lines := strings.Split(h, "<br>")
	var out []string
	var block []string
	flush := func() {
		if len(block) > 0 {
			out = append(out, `<blockquote>`+strings.Join(block, "<br>")+`</blockquote>`)
			block = nil
		}
	}
	for _, l := range lines {
		if strings.HasPrefix(l, "&gt; ") || l == "&gt;" {
			block = append(block, strings.TrimPrefix(strings.TrimPrefix(l, "&gt;"), " "))
			continue
		}
		flush()
		out = append(out, l)
	}
	flush()
	joined := strings.Join(out, "<br>")
	joined = strings.ReplaceAll(joined, "</blockquote><br>", "</blockquote>")
	return joined
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}

func atoi(s string) int {
	n := 0
	if s == "" {
		return -1
	}
	for _, c := range s {
		if c < '0' || c > '9' {
			return -1
		}
		n = n*10 + int(c-'0')
	}
	return n
}
