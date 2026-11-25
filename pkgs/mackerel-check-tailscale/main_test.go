package main

import (
	"testing"

	"github.com/mackerelio/checkers"
	"tailscale.com/ipn/ipnstate"
)

func TestJudge(t *testing.T) {
	online := &ipnstate.PeerStatus{Online: true}
	offline := &ipnstate.PeerStatus{Online: false}
	tests := []struct {
		name   string
		status *ipnstate.Status
		want   checkers.Status
		msg    string
	}{
		{
			name:   "running and online",
			status: &ipnstate.Status{BackendState: "Running", Self: online},
			want:   checkers.OK,
			msg:    "BackendState=Running, Online=true",
		},
		{
			name:   "running but offline",
			status: &ipnstate.Status{BackendState: "Running", Self: offline},
			want:   checkers.CRITICAL,
			msg:    "BackendState=Running, Online=false",
		},
		{
			name:   "running without self",
			status: &ipnstate.Status{BackendState: "Running"},
			want:   checkers.CRITICAL,
			msg:    "BackendState=Running, Online=false",
		},
		{
			name:   "needs login without self",
			status: &ipnstate.Status{BackendState: "NeedsLogin"},
			want:   checkers.CRITICAL,
			msg:    "BackendState=NeedsLogin, Online=false",
		},
		{
			name:   "stopped",
			status: &ipnstate.Status{BackendState: "Stopped", Self: offline},
			want:   checkers.CRITICAL,
			msg:    "BackendState=Stopped, Online=false",
		},
		{
			name:   "stale online flag while stopped",
			status: &ipnstate.Status{BackendState: "Stopped", Self: online},
			want:   checkers.CRITICAL,
			msg:    "BackendState=Stopped, Online=true",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := judge(tt.status)
			if got.Status != tt.want || got.Message != tt.msg {
				t.Errorf("judge() = %v %q, want %v %q", got.Status, got.Message, tt.want, tt.msg)
			}
		})
	}
}
