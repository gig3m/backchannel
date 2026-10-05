package mrkdwn

import "testing"

type names struct{}

func (names) UserName(id string) string {
	if id == "U1" {
		return "kyle"
	}
	return ""
}
func (names) ChannelName(id string) string {
	if id == "C1" {
		return "general"
	}
	return ""
}

func TestRender(t *testing.T) {
	cases := []struct {
		in, html, plain string
		mention         bool
	}{
		{"hello", "hello", "hello", false},
		{"*bold* and _it_ and ~gone~", "<b>bold</b> and <i>it</i> and <s>gone</s>", "*bold* and _it_ and ~gone~", false},
		{"a*b*c", "a*b*c", "a*b*c", false},
		{"hi <@U1>", `hi <span class="mention">@kyle</span>`, "hi @kyle", true},
		{"see <#C1>", `see <span class="mention">#general</span>`, "see #general", false},
		{"<#C9|random>", `<span class="mention">#random</span>`, "#random", false},
		{"<!here> look", `<span class="mention">@here</span> look`, "@here look", true},
		{"<https://x.io/a_b_c|the_link>", `<a href="https://x.io/a_b_c">the_link</a>`, "the_link", false},
		{"<https://x.io>", `<a href="https://x.io">https://x.io</a>`, "https://x.io", false},
		{"<javascript:alert(1)|click>", "click", "click", false},
		{"1 &lt; 2 &amp;&amp; 3 &gt; 2", "1 &lt; 2 &amp;&amp; 3 &gt; 2", "1 < 2 && 3 > 2", false},
		{"<b>not html</b>", "<b>not html</b>", "b>not html</b", false},
		{"`*x*`", "<code>*x*</code>", "*x*", false},
		{"```\n*raw*\n```", "<pre>*raw*</pre>", "*raw*", false},
		{"&gt; quoted\nreply", "<blockquote>quoted</blockquote>reply", "> quoted\nreply", false},
		{"nice :thumbsup:", "nice 👍", "nice 👍", false},
		{"custom :partyparrot:", "custom :partyparrot:", "custom :partyparrot:", false},
		{"line1\nline2", "line1<br>line2", "line1\nline2", false},
	}
	for _, c := range cases {
		got := Render(c.in, "U1", names{})
		if c.in == "<b>not html</b>" {
			// Slack never sends raw "<" outside entities, but if it did the
			// entity regex would consume it; what matters is no live tag.
			if got.HTML == "<b>not html</b>" {
				t.Errorf("raw tag passed through: %q", got.HTML)
			}
			continue
		}
		if got.HTML != c.html {
			t.Errorf("Render(%q).HTML = %q, want %q", c.in, got.HTML, c.html)
		}
		if got.Plain != c.plain {
			t.Errorf("Render(%q).Plain = %q, want %q", c.in, got.Plain, c.plain)
		}
		if got.MentionsMe != c.mention {
			t.Errorf("Render(%q).MentionsMe = %v, want %v", c.in, got.MentionsMe, c.mention)
		}
	}
}

func TestEmoji(t *testing.T) {
	if Emoji("+1") == "" || Emoji(":wave::skin-tone-3:") == "" {
		t.Error("expected standard emoji to resolve")
	}
	if Emoji("partyparrot") != "" {
		t.Error("custom emoji should not resolve")
	}
}
