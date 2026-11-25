package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

// errorBodyLimit bounds how much of an error response is shown.
const errorBodyLimit = 512

// runner is the part of a self-hosted runner that GitHub reports which the
// check looks at.
type runner struct {
	Name   string `json:"name"`
	Status string `json:"status"`
}

// runnerFinder looks up self-hosted runners registered to a repository.
type runnerFinder interface {
	// FindRunner returns the runner registered to the repository under the
	// name, or nil when it is not registered.
	FindRunner(ctx context.Context, repository, name string) (*runner, error)
}

// findRunners asks the finder about each wanted runner and returns the
// registered ones by name.
func findRunners(
	ctx context.Context, finder runnerFinder, repository string, wanted []string,
) (map[string]runner, error) {
	found := map[string]runner{}
	for _, name := range wanted {
		r, err := finder.FindRunner(ctx, repository, name)
		if err != nil {
			return nil, fmt.Errorf("cannot ask GitHub about %s: %w", name, err)
		}
		if r != nil {
			found[name] = *r
		}
	}
	return found, nil
}

// githubClient is a runnerFinder that queries the GitHub REST API.
type githubClient struct {
	http  *http.Client
	api   string
	token string
}

func (c *githubClient) FindRunner(ctx context.Context, repository, name string) (*runner, error) {
	endpoint, err := url.JoinPath(c.api, "repos", repository, "actions", "runners")
	if err != nil {
		return nil, err
	}
	endpoint += "?" + url.Values{"name": {name}}.Encode()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("Authorization", "Bearer "+c.token)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, errorBodyLimit))
		return nil, fmt.Errorf("%s: %s", resp.Status, strings.TrimSpace(string(body)))
	}
	var list struct {
		Runners []runner `json:"runners"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&list); err != nil {
		return nil, fmt.Errorf("cannot decode the runners: %w", err)
	}
	// The filter is applied by GitHub, but the name is compared again so that
	// a similar name is never taken for the wanted runner.
	for _, r := range list.Runners {
		if r.Name == name {
			return &r, nil
		}
	}
	return nil, nil
}
