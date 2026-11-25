package main

import (
	"context"
	"errors"
	"testing"

	"github.com/mackerelio/checkers"
)

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
