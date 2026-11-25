package main

import (
	"context"
	"errors"
	"testing"

	"github.com/mackerelio/checkers"
)

func TestJudge(t *testing.T) {
	errNoReply := errors.New("no reply")
	errSystemd := errors.New("connection refused")
	// states maps a unit to the sub state the fake systemd reports.
	type states map[string]string
	tests := []struct {
		name       string
		pingErr    error
		states     states
		systemdErr error
		wantStatus checkers.Status
		wantMsg    string
	}{
		{
			name:       "ping succeeded",
			wantStatus: checkers.OK,
			wantMsg:    "ping succeeded",
		},
		{
			name:       "garbage collection keeps the VM stopped",
			pingErr:    errNoReply,
			states:     states{"nix-gc.service": "start", "nix-optimise.service": "dead"},
			wantStatus: checkers.OK,
			wantMsg:    "stopped while nix-gc.service is start",
		},
		{
			name:       "store optimisation keeps the VM stopped",
			pingErr:    errNoReply,
			states:     states{"nix-gc.service": "dead", "nix-optimise.service": "stop-post"},
			wantStatus: checkers.OK,
			wantMsg:    "stopped while nix-optimise.service is stop-post",
		},
		{
			name:       "nothing keeps the VM stopped",
			pingErr:    errNoReply,
			states:     states{"nix-gc.service": "start-pre", "nix-optimise.service": "dead"},
			wantStatus: checkers.CRITICAL,
			wantMsg:    "ping failed: no reply",
		},
		{
			name:       "systemd cannot be asked",
			pingErr:    errNoReply,
			systemdErr: errSystemd,
			wantStatus: checkers.CRITICAL,
			wantMsg:    "ping failed: no reply; cannot ask systemd about nix-gc.service: connection refused",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			subStateOf := func(_ context.Context, unit string) (string, error) {
				if tt.pingErr == nil {
					t.Errorf("asked systemd about %s although the ping succeeded", unit)
				}
				if tt.systemdErr != nil {
					return "", tt.systemdErr
				}
				return tt.states[unit], nil
			}
			got := judge(context.Background(), tt.pingErr, subStateOf)
			if got.Status != tt.wantStatus || got.Message != tt.wantMsg {
				t.Errorf("judge() = %v %q, want %v %q", got.Status, got.Message, tt.wantStatus, tt.wantMsg)
			}
		})
	}
}

func TestStopsVM(t *testing.T) {
	tests := []struct {
		subState string
		want     bool
	}{
		{"start", true},
		{"start-post", true},
		{"running", true},
		{"stop", true},
		{"stop-sigterm", true},
		{"stop-sigkill", true},
		{"stop-post", true},
		{"final-sigterm", true},
		{"final-sigkill", true},
		{"dead", false},
		{"failed", false},
		{"condition", false},
		{"start-pre", false},
		{"auto-restart", false},
		{"", false},
	}
	for _, tt := range tests {
		t.Run(tt.subState, func(t *testing.T) {
			if got := stopsVM(tt.subState); got != tt.want {
				t.Errorf("stopsVM(%q) = %t, want %t", tt.subState, got, tt.want)
			}
		})
	}
}
