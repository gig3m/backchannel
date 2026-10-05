VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
PLUGIN_LINK := $(HOME)/.config/omarchy/plugins/gig3m.backchannel
UNIT_DIR := $(HOME)/.config/systemd/user

.PHONY: test build dev reload undev

test:
	cd daemon && go vet ./... && go test ./...

build:
	cd daemon && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=$(VERSION)" -o backchanneld ./cmd/backchanneld

dev: build
	install -Dm755 daemon/backchanneld $(HOME)/.local/bin/backchanneld
	mkdir -p $(UNIT_DIR)
	sed 's#/usr/bin/backchanneld#%h/.local/bin/backchanneld#' daemon/packaging/backchanneld.service > $(UNIT_DIR)/backchanneld.service
	systemctl --user daemon-reload
	systemctl --user restart backchanneld
	ln -sfn $(CURDIR) $(PLUGIN_LINK)
	omarchy-shell shell rescanPlugins || true

reload: build
	install -Dm755 daemon/backchanneld $(HOME)/.local/bin/backchanneld
	systemctl --user restart backchanneld

undev:
	systemctl --user disable --now backchanneld || true
	rm -f $(UNIT_DIR)/backchanneld.service $(HOME)/.local/bin/backchanneld $(PLUGIN_LINK)
	systemctl --user daemon-reload
