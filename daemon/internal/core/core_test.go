package core

import (
	"testing"

	"github.com/slack-go/slack"
)

func TestPrettyGroupName(t *testing.T) {
	if got := prettyGroupName("mpdm-alice--bob--carol-1"); got != "alice, bob, carol" {
		t.Errorf("got %q", got)
	}
}

func TestTsTime(t *testing.T) {
	if tsTime("1700000000.000100").Unix() != 1700000000 {
		t.Error("ts parse")
	}
	if !tsTime("").IsZero() || !tsTime("abc").IsZero() {
		t.Error("bad ts should be zero")
	}
}

func TestKindOf(t *testing.T) {
	ch := func(f func(*slack.Channel)) slack.Channel { var c slack.Channel; f(&c); return c }
	cases := map[string]slack.Channel{
		"dm":      ch(func(c *slack.Channel) { c.IsIM = true }),
		"group":   ch(func(c *slack.Channel) { c.IsMpIM = true }),
		"private": ch(func(c *slack.Channel) { c.IsPrivate = true }),
		"channel": ch(func(c *slack.Channel) {}),
	}
	for want, c := range cases {
		if got := kindOf(c); got != want {
			t.Errorf("kindOf = %q, want %q", got, want)
		}
	}
}

func TestCredentialsValidate(t *testing.T) {
	if (Credentials{UserToken: "xoxp-1", AppToken: "xapp-1"}).Validate() != nil {
		t.Error("good tokens rejected")
	}
	if (Credentials{UserToken: "xoxb-1", AppToken: "xapp-1"}).Validate() == nil {
		t.Error("bot token accepted as user token")
	}
}

func TestCredentialsRoundTrip(t *testing.T) {
	t.Setenv("STATE_DIRECTORY", t.TempDir())
	c := Credentials{UserToken: "xoxp-a", AppToken: "xapp-b"}
	if err := saveCredentials(c); err != nil {
		t.Fatal(err)
	}
	got, err := loadCredentials()
	if err != nil || got == nil || *got != c {
		t.Fatalf("load = %v, %v", got, err)
	}
	if err := deleteCredentials(); err != nil {
		t.Fatal(err)
	}
	if got, _ := loadCredentials(); got != nil {
		t.Error("credentials survived delete")
	}
}

func TestEscapeOutgoing(t *testing.T) {
	if got := escapeOutgoing("a < b && c > d"); got != "a &lt; b &amp;&amp; c &gt; d" {
		t.Errorf("got %q", got)
	}
}

func TestTsBefore(t *testing.T) {
	cases := map[string]string{
		"1700000000.000100": "1700000000.000099",
		"1700000000.000000": "1699999999.999999",
		"1700000000.123456": "1700000000.123455",
		"bad":               "",
		"1.23":              "",
	}
	for in, want := range cases {
		if got := tsBefore(in); got != want {
			t.Errorf("tsBefore(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestEncodeMentions(t *testing.T) {
	dir := &directory{mentions: map[string]string{
		"jane doe": "U1", "jane": "U1", "jdoe": "U1",
		"bob": "U2", "bob.smith": "U3",
	}, longest: 9}
	cases := map[string]string{
		"hi @Jane Doe, ok?":     "hi <@U1>, ok?",
		"@jane":                 "<@U1>",
		"@bob.smith and @bob.":  "<@U3> and <@U2>.",
		"mail jane@example.com": "mail jane@example.com",
		"@bobby":                "@bobby",
		"a < @jdoe & b":         "a &lt; <@U1> &amp; b",
		"@here look":            "@here look",
		"(@Jane Doe)":           "(<@U1>)",
	}
	for in, want := range cases {
		if got := encodeMentions(in, dir); got != want {
			t.Errorf("encodeMentions(%q) = %q, want %q", in, got, want)
		}
	}
	if got := encodeMentions("a < b", nil); got != "a &lt; b" {
		t.Errorf("without a directory: %q", got)
	}
}

func TestThreadOf(t *testing.T) {
	if got := threadOf("https://x.slack.com/archives/C1/p1700000000000200?thread_ts=1700000000.000100&cid=C1"); got != "1700000000.000100" {
		t.Errorf("threadOf = %q", got)
	}
	if got := threadOf("https://x.slack.com/archives/C1/p1700000000000200"); got != "" {
		t.Errorf("threadOf root = %q", got)
	}
}
