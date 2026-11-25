// Command mackerel-check-tailscale is a Mackerel check plugin that reports
// whether this node is connected to the tailnet.
package main

import (
	"context"
	"fmt"
	"time"

	"github.com/mackerelio/checkers"
	"tailscale.com/client/local"
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
	return judge(status.BackendState, status.Self != nil && status.Self.Online)
}

// judge reports OK only when tailscaled is running and the control plane
// sees this node as online.
func judge(backendState string, online bool) *checkers.Checker {
	msg := fmt.Sprintf("BackendState=%s, Online=%t", backendState, online)
	if backendState == "Running" && online {
		return checkers.Ok(msg)
	}
	return checkers.Critical(msg)
}
