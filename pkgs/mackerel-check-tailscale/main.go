// Command mackerel-check-tailscale is a Mackerel check plugin that reports
// whether this node is connected to the tailnet.
package main

import (
	"context"
	"fmt"
	"time"

	"github.com/mackerelio/checkers"
	"tailscale.com/client/local"
	"tailscale.com/ipn/ipnstate"
)

// timeout bounds the request to the local tailscaled.
const timeout = 10 * time.Second

func main() {
	ckr := run()
	ckr.Name = "Tailscale"
	ckr.Exit()
}

func run() *checkers.Checker {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	var client local.Client
	status, err := client.StatusWithoutPeers(ctx)
	if err != nil {
		return checkers.Critical(err.Error())
	}
	return judge(status)
}

// judge reports OK only when tailscaled is running and the control plane
// sees this node as online.
// Self is missing before the node has logged in, which counts as offline.
func judge(status *ipnstate.Status) *checkers.Checker {
	online := status.Self != nil && status.Self.Online
	msg := fmt.Sprintf("BackendState=%s, Online=%t", status.BackendState, online)
	if status.BackendState == "Running" && online {
		return checkers.Ok(msg)
	}
	return checkers.Critical(msg)
}
