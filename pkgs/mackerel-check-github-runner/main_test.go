package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/mackerelio/checkers"
)

func TestRun(t *testing.T) {
	// The fake API reports the runner as online only for the expected token,
	// so the check reaches systemd never and needs no D-Bus.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer secret" {
			http.Error(w, "bad credentials "+got, http.StatusUnauthorized)
			return
		}
		_, _ = w.Write([]byte(`{"total_count":1,"runners":[{"name":"test-0","status":"online"}]}`))
	}))
	defer server.Close()
	dir := t.TempDir()
	writeToken := func(name, content string) string {
		path := filepath.Join(dir, name)
		if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		return path
	}
	tests := []struct {
		name       string
		tokenFile  string
		wantStatus checkers.Status
		wantMsg    string
	}{
		{
			name:       "the newline after the token is dropped",
			tokenFile:  writeToken("token", "secret\n"),
			wantStatus: checkers.OK,
			wantMsg:    "online: test-0",
		},
		{
			name:       "the token file is missing",
			tokenFile:  filepath.Join(dir, "missing"),
			wantStatus: checkers.UNKNOWN,
			wantMsg:    "cannot read the token: open ",
		},
		{
			name:       "the token file is empty",
			tokenFile:  writeToken("empty", " \n"),
			wantStatus: checkers.UNKNOWN,
			wantMsg:    "cannot read the token: the token file is empty",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := run(options{
				label:      "Test Runner",
				api:        server.URL,
				tokenFile:  tt.tokenFile,
				repository: "owner/repo",
				runners:    stringList{"test-0"},
			})
			if got.Status != tt.wantStatus || !strings.HasPrefix(got.Message, tt.wantMsg) {
				t.Errorf("run() = %v %q, want %v %q", got.Status, got.Message, tt.wantStatus, tt.wantMsg)
			}
		})
	}
}

func TestCheck(t *testing.T) {
	// dead reports every unit as not running, so nothing keeps the VM stopped.
	dead := func(context.Context, string) (string, error) { return "dead", nil }
	wanted := []string{"test-0"}
	tests := []struct {
		name       string
		finder     runnerFinder
		wantStatus checkers.Status
		wantMsg    string
	}{
		{
			name: "runner is online",
			finder: fakeFinder{runners: map[[2]string]runner{
				{"owner/repo", "test-0"}: {Name: "test-0", Status: "online"},
			}},
			wantStatus: checkers.OK,
			wantMsg:    "online: test-0",
		},
		{
			name:       "runner is not registered",
			finder:     fakeFinder{},
			wantStatus: checkers.CRITICAL,
			wantMsg:    "test-0 is not registered",
		},
		{
			name:       "GitHub cannot be asked",
			finder:     fakeFinder{err: errors.New("timeout")},
			wantStatus: checkers.UNKNOWN,
			wantMsg:    "cannot ask GitHub about test-0: timeout",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := check("owner/repo", wanted, tt.finder, dead)
			if got.Status != tt.wantStatus || got.Message != tt.wantMsg {
				t.Errorf("check() = %v %q, want %v %q", got.Status, got.Message, tt.wantStatus, tt.wantMsg)
			}
		})
	}
}
