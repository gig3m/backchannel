package core

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/slack-go/slack"
)

var fileIDRe = regexp.MustCompile(`^F[A-Z0-9]+$`)

// fetchFile downloads a private file into the cache and returns its path.
// Slack file URLs need the user token, which the plugin never holds, so
// the plugin shows images from the cached copy.
func (d *Daemon) fetchFile(ctx context.Context, id string) (any, error) {
	api, err := d.client()
	if err != nil {
		return nil, err
	}
	if !fileIDRe.MatchString(id) {
		return nil, errors.New("bad file id")
	}
	dir := filepath.Join(cacheDir(), "files")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	// Cached already?
	if m, _ := filepath.Glob(filepath.Join(dir, id+".*")); len(m) > 0 {
		return map[string]string{"path": m[0]}, nil
	}
	f, _, _, err := api.GetFileInfoContext(ctx, id, 0, 0)
	if err != nil {
		return nil, err
	}
	if f.Size > 50<<20 {
		return nil, fmt.Errorf("%s is larger than 50 MB; open it in Slack", f.Name)
	}
	url := f.URLPrivateDownload
	if url == "" {
		url = f.URLPrivate
	}
	if url == "" {
		return nil, errors.New("this file has no download link")
	}
	ext := strings.ToLower(filepath.Ext(f.Name))
	if ext == "" || len(ext) > 6 {
		ext = "." + strings.ToLower(f.Filetype)
	}
	tmp, err := os.CreateTemp(dir, ".dl-*")
	if err != nil {
		return nil, err
	}
	defer os.Remove(tmp.Name())
	if err := api.GetFileContext(ctx, url, tmp); err != nil {
		tmp.Close()
		return nil, err
	}
	if err := tmp.Close(); err != nil {
		return nil, err
	}
	path := filepath.Join(dir, id+ext)
	if err := os.Rename(tmp.Name(), path); err != nil {
		return nil, err
	}
	return map[string]string{"path": path}, nil
}

// upload sends a local file to a conversation, optionally in a thread with
// a comment.
func (d *Daemon) upload(ctx context.Context, conv, path, comment, threadTS string) (any, error) {
	api, err := d.client()
	if err != nil {
		return nil, err
	}
	if !filepath.IsAbs(path) {
		return nil, errors.New("path must be absolute")
	}
	fi, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	if !fi.Mode().IsRegular() {
		return nil, errors.New("not a regular file")
	}
	sum, err := api.UploadFileContext(ctx, slack.UploadFileParameters{
		File: path, FileSize: int(fi.Size()), Filename: filepath.Base(path),
		Channel: conv, ThreadTimestamp: threadTS, InitialComment: escapeOutgoing(comment),
	})
	if err != nil {
		return nil, err
	}
	return map[string]string{"id": sum.ID}, nil
}
