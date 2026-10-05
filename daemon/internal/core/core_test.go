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
