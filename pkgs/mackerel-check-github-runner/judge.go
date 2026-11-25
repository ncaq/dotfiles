package main

import (
	"context"
	"fmt"
	"strings"

	"github.com/mackerelio/checkers"
)

// storeWriterUnits are the units that stop the VM while they run.
var storeWriterUnits = []string{"nix-gc.service", "nix-optimise.service"}

// unavailable lists why the wanted runners cannot take jobs.
func unavailable(wanted []string, found map[string]runner) []string {
	var reasons []string
	for _, name := range wanted {
		r, ok := found[name]
		switch {
		case !ok:
			reasons = append(reasons, name+" is not registered")
		case r.Status != "online":
			reasons = append(reasons, fmt.Sprintf("%s is %s", name, r.Status))
		}
	}
	return reasons
}

// judge decides the result from what GitHub reports about the runners.
// It asks for the sub states only when a runner is unavailable.
func judge(
	ctx context.Context, wanted []string, found map[string]runner, subStateOf subStateFunc,
) *checkers.Checker {
	reasons := unavailable(wanted, found)
	if len(reasons) == 0 {
		return checkers.Ok("online: " + strings.Join(wanted, ", "))
	}
	summary := strings.Join(reasons, ", ")
	for _, unit := range storeWriterUnits {
		subState, err := subStateOf(ctx, unit)
		if err != nil {
			msg := fmt.Sprintf("%s; cannot ask systemd about %s: %v", summary, unit, err)
			return checkers.Critical(msg)
		}
		if stopsVM(subState) {
			return checkers.Ok(fmt.Sprintf("stopped while %s is %s", unit, subState))
		}
	}
	return checkers.Critical(summary)
}

// stopsVM reports whether a store writer unit in the given sub state is
// keeping the VM stopped.
//
// The VM is down from the end of the pre-start step until the post-stop step
// finishes, including while systemd is killing the main or post-stop process.
// The pre-start step itself, the condition check, and the wait before a retry
// leave the VM running.
func stopsVM(subState string) bool {
	switch subState {
	case "start", "start-post", "running",
		"stop", "stop-sigterm", "stop-sigkill",
		"stop-post", "final-sigterm", "final-sigkill":
		return true
	default:
		return false
	}
}
