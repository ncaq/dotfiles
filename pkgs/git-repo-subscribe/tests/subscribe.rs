use std::fs;
#[cfg(unix)]
use std::os::unix::fs::symlink;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use git_repo_subscribe::{
    BranchName, ConfiguredRemote, Outcome, PartialCloneFilter, PartialCloneFilterError, RemoteUrl,
    RemoteUrlError, Repository, SkipReason, WorktreePath, WorktreePathError, subscribe,
};
use tempfile::TempDir;

struct Fixture {
    temp_dir: TempDir,
    remote: PathBuf,
    remote_url: RemoteUrl,
    source: PathBuf,
    subscription: PathBuf,
    historical_blob: String,
}

impl Fixture {
    fn new() -> Self {
        let temp_dir = tempfile::tempdir().expect("create temporary directory");
        let remote = temp_dir.path().join("remote.git");
        let remote_url = format!("file://{}", remote.display())
            .parse()
            .expect("parse remote URL");
        let source = temp_dir.path().join("source");
        let subscription = temp_dir.path().join("subscription");

        git(["init", "--bare", "--initial-branch=master"], &remote);
        git_in(&remote, ["config", "uploadpack.allowFilter", "true"]);
        git(["init", "--initial-branch=master"], &source);
        let hooks = temp_dir.path().join("hooks");
        fs::create_dir(&hooks).expect("create empty hooks directory");
        git_in(&source, ["config", "core.hooksPath", path_text(&hooks)]);
        git_in(&source, ["config", "user.email", "test@example.com"]);
        git_in(&source, ["config", "user.name", "Test"]);
        git_in(&source, ["remote", "add", "origin", path_text(&remote)]);

        fs::write(source.join("historical"), vec![0; 2 * 1024 * 1024])
            .expect("write historical blob");
        let historical_blob = git_text_in(&source, ["hash-object", "historical"]);
        git_in(&source, ["add", "historical"]);
        git_in(&source, ["commit", "-m", "historical"]);
        fs::remove_file(source.join("historical")).expect("remove historical blob");
        fs::write(source.join("tracked"), "initial\n").expect("write tracked file");
        git_in(&source, ["add", "--all"]);
        git_in(&source, ["commit", "-m", "initial"]);
        git_in(&source, ["push", "-u", "origin", "master"]);

        Self {
            temp_dir,
            remote,
            remote_url,
            source,
            subscription,
            historical_blob,
        }
    }

    fn repository(&self) -> Repository {
        self.repository_at(self.subscription.clone())
    }

    fn repository_at(&self, path: PathBuf) -> Repository {
        Repository::new(
            self.remote_url.clone(),
            WorktreePath::try_from(path).expect("valid worktree path"),
            "blob:limit=1m".parse().expect("valid partial clone filter"),
        )
    }

    fn push_update(&self, content: &str, message: &str) {
        fs::write(self.source.join("tracked"), content).expect("update tracked file");
        git_in(&self.source, ["commit", "-am", message]);
        git_in(&self.source, ["push"]);
    }
}

#[test]
fn clones_partial_repository_with_complete_history() {
    let fixture = Fixture::new();

    assert_eq!(subscribe(&fixture.repository()).unwrap(), Outcome::Cloned);
    assert_eq!(
        git_text_in(&fixture.subscription, ["rev-list", "--count", "HEAD"]),
        "2"
    );
    assert_eq!(
        git_text_in(
            &fixture.subscription,
            ["config", "--get", "remote.origin.partialclonefilter"]
        ),
        "blob:limit=1048576"
    );
    assert_eq!(
        git_text_in(
            &fixture.subscription,
            ["config", "--get", "remote.origin.promisor"]
        ),
        "true"
    );
    assert_eq!(
        git_text_in(
            &fixture.subscription,
            ["rev-parse", "--is-shallow-repository"]
        ),
        "false"
    );
    assert_historical_blob_missing(&fixture);
}

#[test]
fn fast_forwards_clean_default_branch() {
    let fixture = Fixture::new();
    subscribe(&fixture.repository()).unwrap();
    fixture.push_update("updated\n", "update");

    assert_eq!(subscribe(&fixture.repository()).unwrap(), Outcome::Updated);
    assert_eq!(
        git_text_in(&fixture.subscription, ["rev-parse", "HEAD"]),
        git_text_in(&fixture.source, ["rev-parse", "HEAD"])
    );
    assert!(
        git_text_in(
            &fixture.subscription,
            [
                "for-each-ref",
                "--format=%(refname)",
                "refs/git-repo-subscribe"
            ]
        )
        .is_empty()
    );
    assert_historical_blob_missing(&fixture);
}

#[test]
fn skips_diverged_default_branch_without_changing_head() {
    let fixture = Fixture::new();
    subscribe(&fixture.repository()).unwrap();
    git_in(
        &fixture.subscription,
        ["config", "user.email", "test@example.com"],
    );
    git_in(&fixture.subscription, ["config", "user.name", "Test"]);
    git_in(
        &fixture.subscription,
        [
            "config",
            "core.hooksPath",
            path_text(&fixture.temp_dir.path().join("hooks")),
        ],
    );
    fs::write(fixture.subscription.join("tracked"), "local\n").expect("write local update");
    git_in(&fixture.subscription, ["commit", "-am", "local"]);
    let local_head = git_text_in(&fixture.subscription, ["rev-parse", "HEAD"]);
    fixture.push_update("remote\n", "remote");

    let output = subscribe_command(&fixture)
        .output()
        .expect("run subscriber");
    assert_success(output.clone());
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("unable to fast-forward"),
        "unexpected stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        git_text_in(&fixture.subscription, ["rev-parse", "HEAD"]),
        local_head
    );
    assert_eq!(
        subscribe(&fixture.repository()).unwrap(),
        Outcome::Skipped(SkipReason::FastForwardFailed)
    );
}

#[test]
fn skips_non_default_branch() {
    let fixture = Fixture::new();
    subscribe(&fixture.repository()).unwrap();
    git_in(&fixture.subscription, ["switch", "-c", "topic"]);
    fixture.push_update("branch update\n", "branch-update");

    assert_eq!(
        subscribe(&fixture.repository()).unwrap(),
        Outcome::Skipped(SkipReason::NotDefaultBranch {
            current: "topic".parse().unwrap(),
            default: "master".parse().unwrap(),
        })
    );
}

#[test]
fn skips_local_changes() {
    let fixture = Fixture::new();
    subscribe(&fixture.repository()).unwrap();
    fs::write(fixture.subscription.join("untracked"), "dirty\n").expect("write local change");

    assert_eq!(
        subscribe(&fixture.repository()).unwrap(),
        Outcome::Skipped(SkipReason::LocalChanges)
    );
}

#[test]
fn skips_detached_head() {
    let fixture = Fixture::new();
    subscribe(&fixture.repository()).unwrap();
    git_in(&fixture.subscription, ["switch", "--detach"]);

    assert_eq!(
        subscribe(&fixture.repository()).unwrap(),
        Outcome::Skipped(SkipReason::DetachedHead)
    );
}

#[test]
fn skips_non_repository_and_nested_path() {
    let fixture = Fixture::new();
    let not_repository = fixture.temp_dir.path().join("not-a-repository");
    fs::create_dir(&not_repository).expect("create non-repository");
    let repository = fixture.repository_at(not_repository);
    assert_eq!(
        subscribe(&repository).unwrap(),
        Outcome::Skipped(SkipReason::NotWorktree)
    );
    assert_directory_empty(repository.worktree().as_path());

    subscribe(&fixture.repository()).unwrap();
    let nested = fixture.subscription.join("nested");
    fs::create_dir(&nested).expect("create nested directory");
    let repository = fixture.repository_at(nested);
    assert_eq!(
        subscribe(&repository).unwrap(),
        Outcome::Skipped(SkipReason::NotWorktreeRoot)
    );
    assert_directory_empty(repository.worktree().as_path());
}

#[cfg(unix)]
#[test]
fn skips_symbolic_link_destination() {
    let fixture = Fixture::new();
    let destination = fixture.temp_dir.path().join("destination");
    symlink(&destination, &fixture.subscription).expect("create broken symbolic link");

    assert_eq!(
        subscribe(&fixture.repository()).unwrap(),
        Outcome::Skipped(SkipReason::SymbolicLink)
    );
    assert!(!destination.exists());
}

#[test]
fn protects_ignored_file() {
    let fixture = Fixture::new();
    subscribe(&fixture.repository()).unwrap();
    fs::write(fixture.subscription.join(".git/info/exclude"), "ignored\n").expect("ignore file");
    fs::write(
        fixture.subscription.join("ignored"),
        "local ignored content\n",
    )
    .expect("write ignored file");
    fs::write(fixture.source.join("ignored"), "remote content\n").expect("write remote file");
    git_in(&fixture.source, ["add", "ignored"]);
    git_in(&fixture.source, ["commit", "-m", "ignored"]);
    git_in(&fixture.source, ["push"]);

    assert_eq!(
        subscribe(&fixture.repository()).unwrap(),
        Outcome::Skipped(SkipReason::FastForwardFailed)
    );
    assert_eq!(
        fs::read_to_string(fixture.subscription.join("ignored")).unwrap(),
        "local ignored content\n"
    );
}

#[test]
fn skips_different_origin() {
    let fixture = Fixture::new();
    subscribe(&fixture.repository()).unwrap();
    let other_remote = fixture.temp_dir.path().join("other.git");
    let other_remote_url = format!("file://{}", other_remote.display());
    git(
        ["clone", "--bare", path_text(&fixture.remote)],
        &other_remote,
    );
    git_in(
        &fixture.subscription,
        ["remote", "set-url", "origin", &other_remote_url],
    );

    assert_eq!(
        subscribe(&fixture.repository()).unwrap(),
        Outcome::Skipped(SkipReason::OriginMismatch {
            actual: ConfiguredRemote::new(other_remote_url),
        })
    );
}

#[test]
fn skips_repository_without_origin() {
    let fixture = Fixture::new();
    subscribe(&fixture.repository()).unwrap();
    git_in(&fixture.subscription, ["remote", "remove", "origin"]);
    let head = git_text_in(&fixture.subscription, ["rev-parse", "HEAD"]);

    let output = subscribe_command(&fixture)
        .output()
        .expect("run subscriber");
    assert_success(output.clone());
    assert!(
        String::from_utf8_lossy(&output.stderr).contains("has no origin remote"),
        "unexpected stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(
        git_text_in(&fixture.subscription, ["rev-parse", "HEAD"]),
        head
    );
    assert_eq!(
        subscribe(&fixture.repository()).unwrap(),
        Outcome::Skipped(SkipReason::NoOrigin)
    );
}

#[test]
fn validates_remote_urls() {
    assert!(
        "https://github.com/NixOS/nixpkgs.git"
            .parse::<RemoteUrl>()
            .is_ok()
    );
    assert!(
        "ssh://git@github.com/NixOS/nixpkgs.git"
            .parse::<RemoteUrl>()
            .is_ok()
    );
    assert!("file:///tmp/repository.git".parse::<RemoteUrl>().is_ok());
    assert!(matches!(
        "git@github.com:NixOS/nixpkgs.git".parse::<RemoteUrl>(),
        Err(RemoteUrlError::Parse(_))
    ));
    assert!(matches!(
        "git://github.com/NixOS/nixpkgs.git".parse::<RemoteUrl>(),
        Err(RemoteUrlError::UnsupportedScheme(_))
    ));
    assert!(matches!(
        "https://user:password@example.com/repo.git".parse::<RemoteUrl>(),
        Err(RemoteUrlError::Password)
    ));
    assert!(matches!(
        "https://token@example.com/repo.git".parse::<RemoteUrl>(),
        Err(RemoteUrlError::Username)
    ));
    assert!(matches!(
        "https://example.com/repo.git\n".parse::<RemoteUrl>(),
        Err(RemoteUrlError::UnsafeCharacter)
    ));
    assert!(matches!(
        "https://example.com/repo.git\u{1b}".parse::<RemoteUrl>(),
        Err(RemoteUrlError::UnsafeCharacter)
    ));
    assert!(matches!(
        "https://user\\@example.com/repo.git".parse::<RemoteUrl>(),
        Err(RemoteUrlError::Backslash)
    ));
}

#[test]
fn validates_worktree_paths() {
    assert!("/tmp/repository".parse::<WorktreePath>().is_ok());
    assert!(matches!(
        "relative/repository".parse::<WorktreePath>(),
        Err(WorktreePathError::Relative)
    ));
    assert!(matches!(
        "/tmp/../repository".parse::<WorktreePath>(),
        Err(WorktreePathError::NotNormalized)
    ));
    assert!(matches!(
        "/".parse::<WorktreePath>(),
        Err(WorktreePathError::Root)
    ));
}

#[test]
fn validates_partial_clone_filters() {
    assert!("blob:limit=1m".parse::<PartialCloneFilter>().is_ok());
    assert!(
        "combine:blob:none+tree:0"
            .parse::<PartialCloneFilter>()
            .is_ok()
    );
    assert!(matches!(
        "".parse::<PartialCloneFilter>(),
        Err(PartialCloneFilterError::Empty)
    ));
    assert!(matches!(
        "blob:none tree:0".parse::<PartialCloneFilter>(),
        Err(PartialCloneFilterError::UnsafeCharacter)
    ));
    assert!(matches!(
        "blob:none\0".parse::<PartialCloneFilter>(),
        Err(PartialCloneFilterError::UnsafeCharacter)
    ));
    assert!(matches!(
        "blob:none\u{1b}".parse::<PartialCloneFilter>(),
        Err(PartialCloneFilterError::UnsafeCharacter)
    ));
}

#[test]
fn validates_branch_names() {
    assert!("master".parse::<BranchName>().is_ok());
    assert!("invalid..branch".parse::<BranchName>().is_err());
}

fn subscribe_command(fixture: &Fixture) -> Command {
    let mut command = Command::new(env!("CARGO_BIN_EXE_git-repo-subscribe"));
    command
        .env("RUST_LOG", "warn")
        .env("RUST_LOG_STYLE", "never")
        .arg(fixture.remote_url.as_str())
        .arg(&fixture.subscription)
        .arg("blob:limit=1m");
    command
}

fn assert_historical_blob_missing(fixture: &Fixture) {
    let object = Command::new("git")
        .env("GIT_NO_LAZY_FETCH", "1")
        .arg("-C")
        .arg(&fixture.subscription)
        .args(["cat-file", "-e", &fixture.historical_blob])
        .output()
        .expect("inspect historical blob");
    assert!(
        !object.status.success(),
        "historical large blob was fetched"
    );
}

fn assert_directory_empty(path: &Path) {
    assert!(
        fs::read_dir(path).expect("read directory").next().is_none(),
        "{} is not empty",
        path.display()
    );
}

fn git<const N: usize>(args: [&str; N], path: &Path) {
    let mut command = Command::new("git");
    command.args(args).arg(path);
    assert_success(command.output().expect("run git"));
}

fn git_in<const N: usize>(path: &Path, args: [&str; N]) {
    let mut command = Command::new("git");
    command.arg("-C").arg(path).args(args);
    assert_success(command.output().expect("run git"));
}

fn git_text_in<const N: usize>(path: &Path, args: [&str; N]) -> String {
    let mut command = Command::new("git");
    command.arg("-C").arg(path).args(args);
    let output = command.output().expect("run git");
    assert_success(output.clone());
    String::from_utf8(output.stdout)
        .expect("Git output is UTF-8")
        .trim_end()
        .to_owned()
}

fn assert_success(output: Output) {
    assert!(
        output.status.success(),
        "git failed with {}\nstdout: {}\nstderr: {}",
        output.status,
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

fn path_text(path: &Path) -> &str {
    path.to_str().expect("test path is UTF-8")
}
