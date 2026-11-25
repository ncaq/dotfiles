package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// fakeFinder is a runnerFinder that answers from a fixed table.
type fakeFinder struct {
	// runners maps a repository and a runner name to the registered runner.
	runners map[[2]string]runner
	// err is returned for every query when set.
	err error
}

func (f fakeFinder) FindRunner(_ context.Context, repository, name string) (*runner, error) {
	if f.err != nil {
		return nil, f.err
	}
	if r, ok := f.runners[[2]string{repository, name}]; ok {
		return &r, nil
	}
	return nil, nil
}

func TestFindRunners(t *testing.T) {
	ctx := context.Background()
	finder := fakeFinder{runners: map[[2]string]runner{
		{"owner/repo", "test-0"}:  {Name: "test-0", Status: "online"},
		{"owner/other", "test-1"}: {Name: "test-1", Status: "online"},
	}}

	t.Run("registered ones are returned by name", func(t *testing.T) {
		got, err := findRunners(ctx, finder, "owner/repo", []string{"test-0", "test-1"})
		if err != nil {
			t.Fatal(err)
		}
		if len(got) != 1 || got["test-0"] != (runner{Name: "test-0", Status: "online"}) {
			t.Errorf("findRunners() = %v, want only test-0", got)
		}
	})
	t.Run("an error names the runner", func(t *testing.T) {
		failing := fakeFinder{err: errors.New("timeout")}
		_, err := findRunners(ctx, failing, "owner/repo", []string{"test-0"})
		if err == nil || err.Error() != "cannot ask GitHub about test-0: timeout" {
			t.Errorf("findRunners() error = %v", err)
		}
	})
}

func TestGithubClientFindRunner(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/repos/owner/repo/actions/runners" {
			http.NotFound(w, r)
			return
		}
		if got := r.Header.Get("Authorization"); got != "Bearer secret" {
			http.Error(w, "bad credentials "+got, http.StatusUnauthorized)
			return
		}
		// Answers with a similar name too, which must not be taken.
		switch r.URL.Query().Get("name") {
		case "broken":
			_, _ = w.Write([]byte(`{"runners":[`))
		case "test-0":
			_, _ = w.Write([]byte(`{"total_count":2,"runners":[` +
				`{"name":"test-00","status":"offline"},` +
				`{"name":"test-0","status":"online"}]}`))
		default:
			_, _ = w.Write([]byte(`{"total_count":1,"runners":[{"name":"test-00","status":"online"}]}`))
		}
	}))
	defer server.Close()
	client := &githubClient{http: server.Client(), api: server.URL, token: "secret"}
	ctx := context.Background()

	t.Run("registered", func(t *testing.T) {
		got, err := client.FindRunner(ctx, "owner/repo", "test-0")
		if err != nil {
			t.Fatal(err)
		}
		if got == nil || *got != (runner{Name: "test-0", Status: "online"}) {
			t.Errorf("FindRunner() = %v, want test-0 online", got)
		}
	})
	t.Run("not registered", func(t *testing.T) {
		got, err := client.FindRunner(ctx, "owner/repo", "test-1")
		if err != nil {
			t.Fatal(err)
		}
		if got != nil {
			t.Errorf("FindRunner() = %v, want nil", got)
		}
	})
	t.Run("unknown repository", func(t *testing.T) {
		if _, err := client.FindRunner(ctx, "owner/missing", "test-0"); err == nil {
			t.Error("FindRunner() succeeded for a repository that does not exist")
		}
	})
	t.Run("bad token", func(t *testing.T) {
		bad := &githubClient{http: server.Client(), api: server.URL, token: "wrong"}
		_, err := bad.FindRunner(ctx, "owner/repo", "test-0")
		// The status and the body are shown in Mackerel as they are.
		want := "401 Unauthorized: bad credentials Bearer wrong"
		if err == nil || err.Error() != want {
			t.Errorf("FindRunner() error = %v, want %q", err, want)
		}
	})
	t.Run("broken response", func(t *testing.T) {
		_, err := client.FindRunner(ctx, "owner/repo", "broken")
		if err == nil || !strings.HasPrefix(err.Error(), "cannot decode the runners: ") {
			t.Errorf("FindRunner() error = %v, want a decode error", err)
		}
	})
}
