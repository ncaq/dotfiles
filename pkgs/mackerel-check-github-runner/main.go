// Command mackerel-check-github-runner is a Mackerel check plugin that reports
// whether the self-hosted GitHub Actions runners of a VM are registered on
// GitHub and online.
//
// The VM is deliberately stopped while the host collects garbage or optimises
// the store, so missing runners are treated as OK during those periods.
// The conditions are explained in package.nix.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/mackerelio/checkers"
)

const (
	// apiTimeout bounds the queries to GitHub.
	apiTimeout = 10 * time.Second
	// systemdTimeout bounds the queries to systemd.
	systemdTimeout = 10 * time.Second
)

// stringList is a flag that can be given more than once.
type stringList []string

func (l *stringList) String() string { return strings.Join(*l, ",") }

func (l *stringList) Set(value string) error {
	*l = append(*l, value)
	return nil
}

// options are the command line arguments.
type options struct {
	label      string
	api        string
	tokenFile  string
	repository string
	runners    stringList
}

func parseOptions() (options, error) {
	var opts options
	flag.StringVar(&opts.label, "label", "", "name shown in the check result")
	flag.StringVar(&opts.api, "api", "https://api.github.com", "base URL of the GitHub REST API")
	flag.StringVar(&opts.tokenFile, "token-file", "",
		"file holding a token that can read the runners of the repository")
	flag.StringVar(&opts.repository, "repository", "",
		"repository the runners belong to, as OWNER/REPO")
	flag.Var(&opts.runners, "runner", "name of a runner that must be online; may be repeated")
	flag.Parse()
	switch {
	case opts.label == "":
		return opts, errors.New("--label is required")
	case opts.tokenFile == "":
		return opts, errors.New("--token-file is required")
	case opts.repository == "":
		return opts, errors.New("--repository is required")
	case len(opts.runners) == 0:
		return opts, errors.New("--runner is required")
	case flag.NArg() != 0:
		return opts, fmt.Errorf("unexpected arguments: %v", flag.Args())
	}
	return opts, nil
}

func main() {
	opts, err := parseOptions()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		flag.Usage()
		os.Exit(int(checkers.UNKNOWN))
	}
	ckr := run(opts)
	ckr.Name = opts.label
	ckr.Exit()
}

func run(opts options) *checkers.Checker {
	token, err := os.ReadFile(opts.tokenFile)
	if err != nil {
		return checkers.Unknown(fmt.Sprintf("cannot read the token: %v", err))
	}
	client := &githubClient{
		http:  &http.Client{Timeout: apiTimeout},
		api:   opts.api,
		token: strings.TrimSpace(string(token)),
	}
	return check(opts.repository, opts.runners, client, systemdSubState)
}

// check asks the finder about the wanted runners and judges the result.
func check(
	repository string, wanted []string, finder runnerFinder, subStateOf subStateFunc,
) *checkers.Checker {
	apiCtx, cancelAPI := context.WithTimeout(context.Background(), apiTimeout)
	defer cancelAPI()
	found, err := findRunners(apiCtx, finder, repository, wanted)
	if err != nil {
		return checkers.Unknown(err.Error())
	}
	systemdCtx, cancelSystemd := context.WithTimeout(context.Background(), systemdTimeout)
	defer cancelSystemd()
	return judge(systemdCtx, wanted, found, subStateOf)
}
