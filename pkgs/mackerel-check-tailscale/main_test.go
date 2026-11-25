package main

import (
	"testing"

	"github.com/mackerelio/checkers"
)

func TestJudge(t *testing.T) {
	tests := []struct {
		name         string
		backendState string
		online       bool
		want         checkers.Status
	}{
		{"running and online", "Running", true, checkers.OK},
		{"running but offline", "Running", false, checkers.CRITICAL},
		{"stopped", "Stopped", false, checkers.CRITICAL},
		{"needs login", "NeedsLogin", false, checkers.CRITICAL},
		{"stale online flag while stopped", "Stopped", true, checkers.CRITICAL},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := judge(tt.backendState, tt.online)
			if got.Status != tt.want {
				t.Errorf("judge(%q, %t) = %v, want %v", tt.backendState, tt.online, got.Status, tt.want)
			}
		})
	}
}
