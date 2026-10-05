package core

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
)

// Credentials are the two tokens a user copies out of their own Slack app:
// the user OAuth token (xoxp-) that acts as them, and the app-level token
// (xapp-) that opens the Socket Mode connection for live events.
type Credentials struct {
	UserToken string `json:"user_token"`
	AppToken  string `json:"app_token"`
}

func (c Credentials) Validate() error {
	if !strings.HasPrefix(c.UserToken, "xoxp-") {
		return errors.New("the user token starts with xoxp- (Install App → User OAuth Token)")
	}
	if !strings.HasPrefix(c.AppToken, "xapp-") {
		return errors.New("the app token starts with xapp- (Basic Information → App-Level Tokens)")
	}
	return nil
}

// dataDir holds the tokens. Under systemd, StateDirectory= creates it and
// passes it in $STATE_DIRECTORY.
func dataDir() string {
	if d := os.Getenv("STATE_DIRECTORY"); d != "" {
		return d
	}
	if d := os.Getenv("XDG_STATE_HOME"); d != "" {
		return filepath.Join(d, "backchanneld")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "state", "backchanneld")
}

func cacheDir() string {
	if d := os.Getenv("CACHE_DIRECTORY"); d != "" {
		return d
	}
	if d := os.Getenv("XDG_CACHE_HOME"); d != "" {
		return filepath.Join(d, "backchanneld")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".cache", "backchanneld")
}

func credentialsPath() string { return filepath.Join(dataDir(), "credentials.json") }

func loadCredentials() (*Credentials, error) {
	b, err := os.ReadFile(credentialsPath())
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var c Credentials
	if err := json.Unmarshal(b, &c); err != nil {
		return nil, err
	}
	return &c, nil
}

// saveCredentials writes the tokens 0600 inside a 0700 directory, through a
// temp file so a crash never leaves half a file.
func saveCredentials(c Credentials) error {
	dir := dataDir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	b, _ := json.MarshalIndent(c, "", "  ")
	tmp, err := os.CreateTemp(dir, ".credentials-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), credentialsPath())
}

func deleteCredentials() error {
	err := os.Remove(credentialsPath())
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}
