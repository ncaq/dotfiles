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
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/mackerelio/checkers"
)

const (
	// apiTimeout bounds all the queries to GitHub together, not each one.
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

// parseOptions parses the arguments without the command name.
// The error and the usage are printed to output on an error.
func parseOptions(args []string, output io.Writer) (options, error) {
	var opts options
	flags := flag.NewFlagSet("mackerel-check-github-runner", flag.ContinueOnError)
	flags.SetOutput(output)
	flags.StringVar(&opts.label, "label", "", "name shown in the check result")
	flags.StringVar(&opts.api, "api", "https://api.github.com", "base URL of the GitHub REST API")
	flags.StringVar(&opts.tokenFile, "token-file", "",
		"file holding a token that can read the runners of the repository")
	flags.StringVar(&opts.repository, "repository", "",
		"repository the runners belong to, as OWNER/REPO")
	flags.Var(&opts.runners, "runner", "name of a runner that must be online; may be repeated")
	if err := flags.Parse(args); err != nil {
		return opts, err
	}
	err := validateOptions(opts, flags.Args())
	if err != nil {
		fmt.Fprintln(flags.Output(), err)
		flags.Usage()
	}
	return opts, err
}

// validateOptions reports the first missing or unexpected argument.
func validateOptions(opts options, rest []string) error {
	switch {
	case opts.label == "":
		return errors.New("--label is required")
	case opts.tokenFile == "":
		return errors.New("--token-file is required")
	case opts.repository == "":
		return errors.New("--repository is required")
	case len(opts.runners) == 0:
		return errors.New("--runner is required")
	case len(rest) != 0:
		return fmt.Errorf("unexpected arguments: %v", rest)
	}
	return nil
}

func main() {
	opts, err := parseOptions(os.Args[1:], os.Stderr)
	if err != nil {
		os.Exit(int(checkers.UNKNOWN))
	}
	ckr := run(opts)
	ckr.Name = opts.label
	ckr.Exit()
}

func run(opts options) *checkers.Checker {
	token, err := readToken(opts.tokenFile)
	if err != nil {
		return checkers.Unknown(fmt.Sprintf("cannot read the token: %v", err))
	}
	// The deadline comes from the context in check, so the client has none.
	client := &githubClient{
		http:  &http.Client{},
		api:   opts.api,
		token: token,
	}
	return check(opts.repository, opts.runners, client, systemdSubState)
}

// readToken reads the token from the file without the surrounding spaces.
// An empty file is refused here, so that a secret missing from the file is
// not reported as a rejection by GitHub.
func readToken(path string) (string, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	token := strings.TrimSpace(string(content))
	if token == "" {
		return "", errors.New("the token file is empty")
	}
	return token, nil
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
