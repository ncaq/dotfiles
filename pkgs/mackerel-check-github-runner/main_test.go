package main

import "testing"

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
