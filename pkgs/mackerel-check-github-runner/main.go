// Command mackerel-check-github-runner is a Mackerel check plugin that reports
// whether a GitHub Actions runner VM is alive.
//
// The VM is deliberately stopped while the host collects garbage or optimises
// the store, so a missing reply is treated as OK during those periods.
// The conditions are explained in package.nix.
package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/coreos/go-systemd/v22/dbus"
	"github.com/mackerelio/checkers"
	probing "github.com/prometheus-community/pro-bing"
)

const (
	// pingTimeout bounds the wait for a single echo reply.
	pingTimeout = 2 * time.Second
	// systemdTimeout bounds the queries to systemd.
	systemdTimeout = 10 * time.Second
)

// storeWriterUnits are the units that stop the VM while they run.
var storeWriterUnits = []string{"nix-gc.service", "nix-optimise.service"}

func main() {
	if len(os.Args) != 3 {
		fmt.Fprintf(os.Stderr, "usage: %s LABEL ADDRESS\n", os.Args[0])
		os.Exit(int(checkers.UNKNOWN))
	}
	ckr := run(os.Args[2])
	ckr.Name = os.Args[1]
	ckr.Exit()
}

func run(address string) *checkers.Checker {
	ctx, cancel := context.WithTimeout(context.Background(), systemdTimeout)
	defer cancel()
	return judge(ctx, ping(address), systemdSubState)
}

// subStateFunc reports the systemd sub state of a unit.
type subStateFunc func(ctx context.Context, unit string) (string, error)

// judge decides the result from the outcome of the ping.
// It asks for the sub states only when the ping failed.
func judge(ctx context.Context, pingErr error, subStateOf subStateFunc) *checkers.Checker {
	if pingErr == nil {
		return checkers.Ok("ping succeeded")
	}
	for _, unit := range storeWriterUnits {
		subState, err := subStateOf(ctx, unit)
		if err != nil {
			msg := fmt.Sprintf("ping failed: %v; cannot ask systemd about %s: %v", pingErr, unit, err)
			return checkers.Critical(msg)
		}
		if stopsVM(subState) {
			return checkers.Ok(fmt.Sprintf("stopped while %s is %s", unit, subState))
		}
	}
	return checkers.Critical(fmt.Sprintf("ping failed: %v", pingErr))
}

// systemdSubState asks systemd over D-Bus for the sub state of a unit.
func systemdSubState(ctx context.Context, unit string) (string, error) {
	conn, err := dbus.NewSystemConnectionContext(ctx)
	if err != nil {
		return "", err
	}
	defer conn.Close()
	property, err := conn.GetUnitPropertyContext(ctx, unit, "SubState")
	if err != nil {
		return "", err
	}
	value := property.Value.Value()
	subState, ok := value.(string)
	if !ok {
		return "", fmt.Errorf("unexpected SubState type %T", value)
	}
	return subState, nil
}

// ping sends one ICMP echo request and reports why no reply arrived.
func ping(address string) error {
	pinger, err := probing.NewPinger(address)
	if err != nil {
		return err
	}
	pinger.SetPrivileged(true)
	pinger.Count = 1
	pinger.Timeout = pingTimeout
	if err := pinger.Run(); err != nil {
		return err
	}
	if pinger.Statistics().PacketsRecv == 0 {
		return fmt.Errorf("no reply from %s", address)
	}
	return nil
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
