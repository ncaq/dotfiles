package main

import (
	"context"
	"errors"
	"testing"

	"github.com/mackerelio/checkers"
)

func TestJudge(t *testing.T) {
	errSystemd := errors.New("connection refused")
	// states maps a unit to the sub state the fake systemd reports.
	type states map[string]string
	online := map[string]runner{"test-0": {Name: "test-0", Status: "online"}}
	tests := []struct {
		name       string
		found      map[string]runner
		states     states
		systemdErr error
		wantStatus checkers.Status
		wantMsg    string
	}{
		{
			name:       "runner is online",
			found:      online,
			wantStatus: checkers.OK,
			wantMsg:    "online: test-0",
		},
		{
			name:       "garbage collection keeps the VM stopped",
			states:     states{"nix-gc.service": "start", "nix-optimise.service": "dead"},
			wantStatus: checkers.OK,
			wantMsg:    "stopped while nix-gc.service is start",
		},
		{
			name:       "store optimisation keeps the VM stopped",
			found:      map[string]runner{"test-0": {Name: "test-0", Status: "offline"}},
			states:     states{"nix-gc.service": "dead", "nix-optimise.service": "stop-post"},
			wantStatus: checkers.OK,
			wantMsg:    "stopped while nix-optimise.service is stop-post",
		},
		{
			name:       "runner is not registered and nothing keeps the VM stopped",
			states:     states{"nix-gc.service": "start-pre", "nix-optimise.service": "dead"},
			wantStatus: checkers.CRITICAL,
			wantMsg:    "test-0 is not registered",
		},
		{
			name:       "runner is offline and nothing keeps the VM stopped",
			found:      map[string]runner{"test-0": {Name: "test-0", Status: "offline"}},
			states:     states{"nix-gc.service": "dead", "nix-optimise.service": "dead"},
			wantStatus: checkers.CRITICAL,
			wantMsg:    "test-0 is offline",
		},
		{
			name:       "systemd cannot be asked",
			systemdErr: errSystemd,
			wantStatus: checkers.CRITICAL,
			wantMsg: "test-0 is not registered; " +
				"cannot ask systemd about nix-gc.service: connection refused",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			wanted := []string{"test-0"}
			subStateOf := func(_ context.Context, unit string) (string, error) {
				if len(unavailable(wanted, tt.found)) == 0 {
					t.Errorf("asked systemd about %s although the runners are online", unit)
				}
				if tt.systemdErr != nil {
					return "", tt.systemdErr
				}
				return tt.states[unit], nil
			}
			got := judge(context.Background(), wanted, tt.found, subStateOf)
			if got.Status != tt.wantStatus || got.Message != tt.wantMsg {
				t.Errorf("judge() = %v %q, want %v %q", got.Status, got.Message, tt.wantStatus, tt.wantMsg)
			}
		})
	}
}

func TestUnavailable(t *testing.T) {
	wanted := []string{"test-0", "test-1", "test-2"}
	found := map[string]runner{
		"test-0": {Name: "test-0", Status: "online"},
		"test-2": {Name: "test-2", Status: "offline"},
	}
	got := unavailable(wanted, found)
	want := []string{"test-1 is not registered", "test-2 is offline"}
	if len(got) != len(want) || got[0] != want[0] || got[1] != want[1] {
		t.Errorf("unavailable() = %q, want %q", got, want)
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
