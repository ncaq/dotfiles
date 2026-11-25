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
	single := []string{"test-0"}
	pair := []string{"test-0", "test-1"}
	online := func(name string) runner { return runner{Name: name, Status: "online"} }
	offline := func(name string) runner { return runner{Name: name, Status: "offline"} }
	tests := []struct {
		name             string
		wanted           []string
		found            map[string]runner
		states           states
		systemdErr       error
		wantSystemdAsked bool
		wantStatus       checkers.Status
		wantMsg          string
	}{
		{
			name:       "runner is online",
			wanted:     single,
			found:      map[string]runner{"test-0": online("test-0")},
			wantStatus: checkers.OK,
			wantMsg:    "online: test-0",
		},
		{
			name:       "every runner is online",
			wanted:     pair,
			found:      map[string]runner{"test-0": online("test-0"), "test-1": online("test-1")},
			wantStatus: checkers.OK,
			wantMsg:    "online: test-0, test-1",
		},
		{
			name:             "garbage collection keeps the VM stopped",
			wanted:           single,
			states:           states{"nix-gc.service": "start", "nix-optimise.service": "dead"},
			wantSystemdAsked: true,
			wantStatus:       checkers.OK,
			wantMsg:          "stopped while nix-gc.service is start",
		},
		{
			name:             "store optimisation keeps the VM stopped",
			wanted:           single,
			found:            map[string]runner{"test-0": offline("test-0")},
			states:           states{"nix-gc.service": "dead", "nix-optimise.service": "stop-post"},
			wantSystemdAsked: true,
			wantStatus:       checkers.OK,
			wantMsg:          "stopped while nix-optimise.service is stop-post",
		},
		{
			name:             "runner is not registered and nothing keeps the VM stopped",
			wanted:           single,
			states:           states{"nix-gc.service": "start-pre", "nix-optimise.service": "dead"},
			wantSystemdAsked: true,
			wantStatus:       checkers.CRITICAL,
			wantMsg:          "test-0 is not registered",
		},
		{
			name:             "runner is offline and nothing keeps the VM stopped",
			wanted:           single,
			found:            map[string]runner{"test-0": offline("test-0")},
			states:           states{"nix-gc.service": "dead", "nix-optimise.service": "dead"},
			wantSystemdAsked: true,
			wantStatus:       checkers.CRITICAL,
			wantMsg:          "test-0 is offline",
		},
		{
			name:             "one of the runners is online and the other is not",
			wanted:           pair,
			found:            map[string]runner{"test-0": online("test-0")},
			states:           states{"nix-gc.service": "dead", "nix-optimise.service": "dead"},
			wantSystemdAsked: true,
			wantStatus:       checkers.CRITICAL,
			wantMsg:          "test-1 is not registered",
		},
		{
			name:             "the reasons of every runner are joined",
			wanted:           pair,
			found:            map[string]runner{"test-1": offline("test-1")},
			states:           states{"nix-gc.service": "dead", "nix-optimise.service": "dead"},
			wantSystemdAsked: true,
			wantStatus:       checkers.CRITICAL,
			wantMsg:          "test-0 is not registered, test-1 is offline",
		},
		{
			name:             "systemd cannot be asked",
			wanted:           single,
			systemdErr:       errSystemd,
			wantSystemdAsked: true,
			wantStatus:       checkers.CRITICAL,
			wantMsg: "test-0 is not registered; " +
				"cannot ask systemd about nix-gc.service: connection refused",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			asked := false
			subStateOf := func(_ context.Context, unit string) (string, error) {
				asked = true
				if tt.systemdErr != nil {
					return "", tt.systemdErr
				}
				return tt.states[unit], nil
			}
			got := judge(context.Background(), tt.wanted, tt.found, subStateOf)
			if got.Status != tt.wantStatus || got.Message != tt.wantMsg {
				t.Errorf("judge() = %v %q, want %v %q", got.Status, got.Message, tt.wantStatus, tt.wantMsg)
			}
			if asked != tt.wantSystemdAsked {
				t.Errorf("judge() asked systemd = %t, want %t", asked, tt.wantSystemdAsked)
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
