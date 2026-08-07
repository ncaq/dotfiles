//! Clone configured Git repositories and safely fast-forward existing worktrees.
//!
//! The crate validates repository configuration before invoking the Git CLI. Existing
//! worktrees are updated only when they point to the configured remote, are clean, and
//! have the remote default branch checked out.

#![deny(missing_docs)]

mod domain;

use std::ffi::{OsStr, OsString};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Output, Stdio};

use log::warn;
use thiserror::Error;

pub use domain::{
    BranchName, ConfiguredRemote, PartialCloneFilter, PartialCloneFilterError, RemoteUrl,
    RemoteUrlError, WorktreePath, WorktreePathError,
};
use domain::{CommitId, TemporaryRef};

#[derive(Debug)]
/// A validated Git repository subscription.
///
/// Its fields are immutable and can only be constructed from validated domain values.
pub struct Repository {
    remote: RemoteUrl,
    worktree: WorktreePath,
    partial_clone_filter: PartialCloneFilter,
}

impl Repository {
    /// Creates a repository subscription from validated configuration values.
    #[must_use]
    pub fn new(
        remote: RemoteUrl,
        worktree: WorktreePath,
        partial_clone_filter: PartialCloneFilter,
    ) -> Self {
        Self {
            remote,
            worktree,
            partial_clone_filter,
        }
    }

    /// Returns the configured remote URL.
    #[must_use]
    pub fn remote(&self) -> &RemoteUrl {
        &self.remote
    }

    /// Returns the local worktree path.
    #[must_use]
    pub fn worktree(&self) -> &WorktreePath {
        &self.worktree
    }

    /// Returns the filter used only when initially cloning the repository.
    #[must_use]
    pub fn partial_clone_filter(&self) -> &PartialCloneFilter {
        &self.partial_clone_filter
    }
}

#[derive(Debug, Eq, PartialEq)]
/// The result of processing a repository subscription.
pub enum Outcome {
    /// A missing worktree was cloned.
    Cloned,
    /// An existing worktree was successfully fast-forwarded or was already current.
    Updated,
    /// Updating was safely skipped for the contained reason.
    Skipped(SkipReason),
}

#[derive(Debug, Eq, PartialEq)]
/// A non-fatal condition that prevents a safe update.
pub enum SkipReason {
    /// The configured path is a symbolic link.
    SymbolicLink,
    /// The configured path exists but is not a Git worktree.
    NotWorktree,
    /// The configured path is inside a worktree but is not its root.
    NotWorktreeRoot,
    /// The worktree has no `origin` remote.
    NoOrigin,
    /// The configured and actual `origin` URLs differ.
    OriginMismatch {
        /// The URL currently configured for `origin`.
        actual: ConfiguredRemote,
    },
    /// The worktree contains tracked or untracked local changes.
    LocalChanges,
    /// The worktree has a detached `HEAD`.
    DetachedHead,
    /// The worktree has no commit checked out yet.
    UnbornHead,
    /// The remote could not be queried for its default branch.
    RemoteUnavailable,
    /// The remote response did not identify a default branch.
    DefaultBranchUnknown,
    /// The checked-out branch is not the remote default branch.
    NotDefaultBranch {
        /// The branch currently checked out in the worktree.
        current: BranchName,
        /// The default branch reported by the remote.
        default: BranchName,
    },
    /// Fetching the default branch failed.
    FetchFailed,
    /// The `origin` URL changed while the fetch was running.
    OriginChanged,
    /// `HEAD` changed while the fetch was running.
    HeadChanged,
    /// The checked-out branch changed while the fetch was running.
    BranchChanged,
    /// The worktree gained local changes while the fetch was running.
    LocalChangesDuringFetch,
    /// The fetched commit could not be merged with a fast-forward.
    FastForwardFailed,
}

impl SkipReason {
    /// Formats a human-readable warning for this skip reason and repository.
    #[must_use]
    pub fn warning(&self, repository: &Repository) -> String {
        let path = repository.worktree();
        match self {
            Self::SymbolicLink => {
                format!("{path} is a symbolic link; skipping update.")
            }
            Self::NotWorktree => format!("{path} is not a Git worktree; skipping update."),
            Self::NotWorktreeRoot => {
                format!("{path} is not the root of its Git worktree; skipping update.")
            }
            Self::NoOrigin => format!("{path} has no origin remote; skipping update."),
            Self::OriginMismatch { actual } => format!(
                "origin URL of {path} is {actual}, expected {}; skipping update.",
                repository.remote()
            ),
            Self::LocalChanges => format!("{path} has local changes; skipping update."),
            Self::DetachedHead => format!("{path} has a detached HEAD; skipping update."),
            Self::UnbornHead => format!("{path} has an unborn HEAD; skipping update."),
            Self::RemoteUnavailable => format!(
                "unable to query the default branch of {}; skipping update.",
                repository.remote()
            ),
            Self::DefaultBranchUnknown => format!(
                "unable to determine the default branch of {}; skipping update.",
                repository.remote()
            ),
            Self::NotDefaultBranch { current, default } => format!(
                "{path} is on {current}, not the default branch {default}; skipping update."
            ),
            Self::FetchFailed => {
                format!("unable to fetch {}; skipping update.", repository.remote())
            }
            Self::OriginChanged => {
                format!("origin URL of {path} changed while fetching; skipping update.")
            }
            Self::HeadChanged => format!("HEAD of {path} changed while fetching; skipping update."),
            Self::BranchChanged => {
                format!("branch of {path} changed while fetching; skipping update.")
            }
            Self::LocalChangesDuringFetch => {
                format!("{path} gained local changes while fetching; skipping update.")
            }
            Self::FastForwardFailed => {
                format!("unable to fast-forward {path}; skipping update.")
            }
        }
    }
}

#[derive(Debug, Error)]
/// A fatal failure while processing a repository subscription.
pub enum SubscribeError {
    /// A missing parent directory could not be created.
    #[error("failed to create {}: {source}", .path.display())]
    CreateParent {
        /// The parent directory that could not be created.
        path: PathBuf,
        /// The underlying filesystem error.
        source: std::io::Error,
    },
    /// The configured worktree path could not be inspected.
    #[error("failed to inspect {}: {source}", .path.display())]
    InspectWorktree {
        /// The path that could not be inspected.
        path: PathBuf,
        /// The underlying filesystem error.
        source: std::io::Error,
    },
    /// The Git executable could not be started.
    #[error("failed to run git {}: {source}", display_args(.args))]
    RunGit {
        /// The Git arguments that could not be executed.
        args: Vec<OsString>,
        /// The underlying process creation error.
        source: std::io::Error,
    },
    /// A Git command required for the operation exited unsuccessfully.
    #[error("git {} failed with {status}", display_args(.args))]
    GitFailed {
        /// The arguments passed to Git.
        args: Vec<OsString>,
        /// The unsuccessful Git exit status.
        status: ExitStatus,
    },
    /// Git returned output that was not valid UTF-8.
    #[error("git {} returned non-UTF-8 output: {source}", display_args(.args))]
    InvalidGitOutput {
        /// The arguments passed to Git.
        args: Vec<OsString>,
        /// The UTF-8 decoding error.
        source: std::string::FromUtf8Error,
    },
    /// A filesystem path could not be resolved to its canonical form.
    #[error("failed to resolve {}: {source}", .path.display())]
    Canonicalize {
        /// The path that could not be resolved.
        path: PathBuf,
        /// The underlying filesystem error.
        source: std::io::Error,
    },
    /// Git returned a branch name that is invalid according to Git's rules.
    #[error("Git returned an invalid branch name: {0}")]
    InvalidBranch(#[from] domain::BranchNameError),
    /// Git returned an invalid full object ID.
    #[error("Git returned an invalid commit ID: {0}")]
    InvalidCommitId(#[from] gix_hash::decode::Error),
}

impl SubscribeError {
    /// Returns the process exit code corresponding to this fatal error.
    #[must_use]
    pub fn exit_code(&self) -> u8 {
        match self {
            Self::GitFailed { status, .. } => status
                .code()
                .and_then(|code| u8::try_from(code).ok())
                .unwrap_or(1),
            _ => 1,
        }
    }

    /// Returns whether Git already emitted the user-facing failure details.
    #[must_use]
    pub fn is_git_failure(&self) -> bool {
        matches!(self, Self::GitFailed { .. })
    }
}

/// Clones a missing repository or safely updates an existing worktree.
///
/// Existing worktrees are updated only when they are clean, use the configured `origin`,
/// and have the remote default branch checked out. Expected unsafe states are returned as
/// [`Outcome::Skipped`], while process and data errors are returned as [`SubscribeError`].
pub fn subscribe(repository: &Repository) -> Result<Outcome, SubscribeError> {
    let worktree = repository.worktree().as_path();
    let worktree_metadata = match fs::symlink_metadata(worktree) {
        Ok(metadata) => Some(metadata),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
        Err(source) => {
            return Err(SubscribeError::InspectWorktree {
                path: worktree.to_path_buf(),
                source,
            });
        }
    };
    if worktree_metadata
        .as_ref()
        .is_some_and(|metadata| metadata.file_type().is_symlink())
    {
        return Ok(Outcome::Skipped(SkipReason::SymbolicLink));
    }
    if worktree_metadata.is_none() {
        if let Some(parent) = worktree.parent()
            && !parent.as_os_str().is_empty()
        {
            fs::create_dir_all(parent).map_err(|source| SubscribeError::CreateParent {
                path: parent.to_path_buf(),
                source,
            })?;
        }
        git_status_checked([
            OsStr::new("clone"),
            OsStr::new(&repository.partial_clone_filter().git_argument()),
            OsStr::new("--single-branch"),
            OsStr::new("--"),
            OsStr::new(repository.remote().as_str()),
            worktree.as_os_str(),
        ])?;
        return Ok(Outcome::Cloned);
    }

    if git_optional_text_in_quiet(worktree, ["rev-parse", "--is-inside-work-tree"])?.as_deref()
        != Some("true")
    {
        return Ok(Outcome::Skipped(SkipReason::NotWorktree));
    }

    let worktree_root = git_text_in(worktree, ["rev-parse", "--show-toplevel"])?;
    if canonicalize(worktree)? != canonicalize(Path::new(&worktree_root))? {
        return Ok(Outcome::Skipped(SkipReason::NotWorktreeRoot));
    }

    let Some(origin_url) = origin_url(worktree)? else {
        return Ok(Outcome::Skipped(SkipReason::NoOrigin));
    };
    if &origin_url != repository.remote() {
        return Ok(Outcome::Skipped(SkipReason::OriginMismatch {
            actual: ConfiguredRemote::new(origin_url.to_string()),
        }));
    }

    let Some(initial_branch) = current_branch(worktree)? else {
        return Ok(Outcome::Skipped(SkipReason::DetachedHead));
    };

    if has_local_changes(worktree)? {
        return Ok(Outcome::Skipped(SkipReason::LocalChanges));
    }

    let remote_head_args = [
        "ls-remote",
        "--symref",
        "--",
        repository.remote().as_str(),
        "HEAD",
    ];
    let remote_head = git_output(remote_head_args)?;
    if !remote_head.status.success() {
        return Ok(Outcome::Skipped(SkipReason::RemoteUnavailable));
    }
    let remote_head = output_text(remote_head_args, remote_head.stdout)?;
    let Some(default_branch) = parse_default_branch(&remote_head)? else {
        return Ok(Outcome::Skipped(SkipReason::DefaultBranchUnknown));
    };
    if initial_branch != default_branch {
        return Ok(Outcome::Skipped(SkipReason::NotDefaultBranch {
            current: initial_branch,
            default: default_branch,
        }));
    }

    let Some(initial_head) = optional_head_id(worktree)? else {
        return Ok(Outcome::Skipped(SkipReason::UnbornHead));
    };

    let fetch_ref = TemporaryRef::for_current_process();
    let refspec = format!(
        "+refs/heads/{}:{}",
        initial_branch.as_str(),
        fetch_ref.as_str()
    );
    let tracking_refspec = format!(
        "+refs/heads/{}:refs/remotes/origin/{}",
        initial_branch.as_str(),
        initial_branch.as_str()
    );
    let initial_state = WorktreeState {
        origin: Some(origin_url),
        head: initial_head,
        branch: Some(initial_branch),
    };

    let _fetch_ref_guard = FetchRefGuard {
        worktree,
        fetch_ref: &fetch_ref,
    };
    if !git_status_in(
        worktree,
        [
            "fetch",
            "--no-write-fetch-head",
            "origin",
            &refspec,
            &tracking_refspec,
        ],
        false,
    )? {
        return Ok(Outcome::Skipped(SkipReason::FetchFailed));
    }

    let current_state = WorktreeState::read(worktree)?;
    if let Some(reason) = detect_concurrent_change(&initial_state, &current_state, || {
        has_local_changes(worktree)
    })? {
        return Ok(Outcome::Skipped(reason));
    }
    if !git_status_in(
        worktree,
        [
            "merge",
            "--ff-only",
            "--no-overwrite-ignore",
            fetch_ref.as_str(),
        ],
        false,
    )? {
        return Ok(Outcome::Skipped(SkipReason::FastForwardFailed));
    }

    Ok(Outcome::Updated)
}

fn has_local_changes(path: &Path) -> Result<bool, SubscribeError> {
    Ok(!git_text_in(
        path,
        [
            "-c",
            "core.untrackedCache=true",
            "status",
            "--porcelain=v1",
            "--untracked-files=normal",
        ],
    )?
    .is_empty())
}

fn current_branch(path: &Path) -> Result<Option<BranchName>, SubscribeError> {
    git_optional_text_in(path, ["symbolic-ref", "--quiet", "HEAD"])?
        .map(|branch| {
            BranchName::parse(
                branch
                    .strip_prefix("refs/heads/")
                    .unwrap_or(&branch)
                    .to_owned(),
            )
        })
        .transpose()
        .map_err(Into::into)
}

fn origin_url(path: &Path) -> Result<Option<ConfiguredRemote>, SubscribeError> {
    git_optional_text_in(path, ["remote", "get-url", "origin"])
        .map(|origin| origin.map(ConfiguredRemote::new))
}

fn parse_default_branch(remote_head: &str) -> Result<Option<BranchName>, SubscribeError> {
    remote_head
        .lines()
        .find_map(|line| {
            line.strip_prefix("ref: refs/heads/")
                .and_then(|value| value.strip_suffix("\tHEAD"))
                .map(|value| BranchName::parse(value.to_owned()))
        })
        .transpose()
        .map_err(Into::into)
}

fn head_id(path: &Path) -> Result<CommitId, SubscribeError> {
    CommitId::parse(&git_text_in(path, ["rev-parse", "HEAD"])?).map_err(Into::into)
}

fn optional_head_id(path: &Path) -> Result<Option<CommitId>, SubscribeError> {
    git_optional_text_in(path, ["rev-parse", "--verify", "HEAD"])?
        .map(|head| CommitId::parse(&head))
        .transpose()
        .map_err(Into::into)
}

#[derive(Debug, Eq, PartialEq)]
struct WorktreeState {
    origin: Option<ConfiguredRemote>,
    head: CommitId,
    branch: Option<BranchName>,
}

impl WorktreeState {
    fn read(path: &Path) -> Result<Self, SubscribeError> {
        Ok(Self {
            origin: origin_url(path)?,
            head: head_id(path)?,
            branch: current_branch(path)?,
        })
    }
}

fn detect_concurrent_change<E>(
    initial: &WorktreeState,
    current: &WorktreeState,
    has_local_changes: impl FnOnce() -> Result<bool, E>,
) -> Result<Option<SkipReason>, E> {
    if current.origin != initial.origin {
        Ok(Some(SkipReason::OriginChanged))
    } else if current.head != initial.head {
        Ok(Some(SkipReason::HeadChanged))
    } else if current.branch != initial.branch {
        Ok(Some(SkipReason::BranchChanged))
    } else if has_local_changes()? {
        Ok(Some(SkipReason::LocalChangesDuringFetch))
    } else {
        Ok(None)
    }
}

fn canonicalize(path: &Path) -> Result<PathBuf, SubscribeError> {
    path.canonicalize()
        .map_err(|source| SubscribeError::Canonicalize {
            path: path.to_path_buf(),
            source,
        })
}

fn git_text_in<I, S>(path: &Path, args: I) -> Result<String, SubscribeError>
where
    I: IntoIterator<Item = S> + Clone,
    S: AsRef<OsStr>,
{
    let output = git_output_in(path, args.clone())?;
    if !output.status.success() {
        return Err(git_failed(args, output.status));
    }
    output_text(args, output.stdout)
}

fn git_optional_text_in<I, S>(path: &Path, args: I) -> Result<Option<String>, SubscribeError>
where
    I: IntoIterator<Item = S> + Clone,
    S: AsRef<OsStr>,
{
    let output = git_output_in(path, args.clone())?;
    if output.status.success() {
        output_text(args, output.stdout).map(Some)
    } else {
        Ok(None)
    }
}

fn git_optional_text_in_quiet<I, S>(path: &Path, args: I) -> Result<Option<String>, SubscribeError>
where
    I: IntoIterator<Item = S> + Clone,
    S: AsRef<OsStr>,
{
    let collected = collect_args(args.clone());
    let output = git_command()
        .arg("-C")
        .arg(path)
        .args(&collected)
        .stderr(Stdio::null())
        .output()
        .map_err(|source| SubscribeError::RunGit {
            args: collected,
            source,
        })?;
    if output.status.success() {
        output_text(args, output.stdout).map(Some)
    } else {
        Ok(None)
    }
}

fn git_status_in<I, S>(path: &Path, args: I, quiet: bool) -> Result<bool, SubscribeError>
where
    I: IntoIterator<Item = S> + Clone,
    S: AsRef<OsStr>,
{
    let collected = collect_args(args.clone());
    let mut command = git_command();
    command.arg("-C").arg(path).args(&collected);
    if quiet {
        command.stdout(Stdio::null());
        command.stderr(Stdio::null());
    }
    command
        .status()
        .map(|status| status.success())
        .map_err(|source| SubscribeError::RunGit {
            args: collected,
            source,
        })
}

fn git_status_checked<I, S>(args: I) -> Result<(), SubscribeError>
where
    I: IntoIterator<Item = S> + Clone,
    S: AsRef<OsStr>,
{
    let collected = collect_args(args.clone());
    let status =
        git_command()
            .args(&collected)
            .status()
            .map_err(|source| SubscribeError::RunGit {
                args: collected.clone(),
                source,
            })?;
    if status.success() {
        Ok(())
    } else {
        Err(SubscribeError::GitFailed {
            args: collected,
            status,
        })
    }
}

fn git_output<I, S>(args: I) -> Result<Output, SubscribeError>
where
    I: IntoIterator<Item = S> + Clone,
    S: AsRef<OsStr>,
{
    let collected = collect_args(args);
    let output = git_command()
        .args(&collected)
        .stderr(Stdio::inherit())
        .output()
        .map_err(|source| SubscribeError::RunGit {
            args: collected.clone(),
            source,
        })?;
    Ok(output)
}

fn git_output_in<I, S>(path: &Path, args: I) -> Result<Output, SubscribeError>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    let collected = collect_args(args);
    git_command()
        .arg("-C")
        .arg(path)
        .args(&collected)
        .stderr(Stdio::inherit())
        .output()
        .map_err(|source| SubscribeError::RunGit {
            args: collected,
            source,
        })
}

fn output_text<I, S>(args: I, stdout: Vec<u8>) -> Result<String, SubscribeError>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    String::from_utf8(stdout)
        .map(|text| text.trim_end_matches(['\n', '\r']).to_owned())
        .map_err(|source| SubscribeError::InvalidGitOutput {
            args: collect_args(args),
            source,
        })
}

fn git_command() -> Command {
    let mut command = Command::new("git");
    let ssh_command = [
        "ssh",
        "-oBatchMode=yes",
        "-oConnectTimeout=60",
        "-oServerAliveInterval=15",
        "-oServerAliveCountMax=4",
    ]
    .join(" ");
    for variable in [
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_COMMON_DIR",
        "GIT_CEILING_DIRECTORIES",
        "GIT_CONFIG",
        "GIT_CONFIG_COUNT",
        "GIT_CONFIG_GLOBAL",
        "GIT_CONFIG_NOSYSTEM",
        "GIT_CONFIG_PARAMETERS",
        "GIT_CONFIG_SYSTEM",
        "GIT_DIR",
        "GIT_DISCOVERY_ACROSS_FILESYSTEM",
        "GIT_EXEC_PATH",
        "GIT_GRAFT_FILE",
        "GIT_INDEX_FILE",
        "GIT_NAMESPACE",
        "GIT_OBJECT_DIRECTORY",
        "GIT_PROXY_COMMAND",
        "GIT_SHALLOW_FILE",
        "GIT_SSH_VARIANT",
        "GIT_TEMPLATE_DIR",
        "GIT_WORK_TREE",
    ] {
        command.env_remove(variable);
    }
    command
        .current_dir("/")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_SYSTEM", "/dev/null")
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("GIT_ASKPASS", "false")
        .env("SSH_ASKPASS", "false")
        .env("GIT_SSH_COMMAND", ssh_command)
        .env("GIT_HTTP_LOW_SPEED_LIMIT", "1")
        .env("GIT_HTTP_LOW_SPEED_TIME", "60");
    command
}

fn git_failed<I, S>(args: I, status: ExitStatus) -> SubscribeError
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    SubscribeError::GitFailed {
        args: collect_args(args),
        status,
    }
}

fn collect_args<I, S>(args: I) -> Vec<OsString>
where
    I: IntoIterator<Item = S>,
    S: AsRef<OsStr>,
{
    args.into_iter()
        .map(|arg| arg.as_ref().to_os_string())
        .collect()
}

fn display_args(args: &[OsString]) -> String {
    args.iter()
        .map(|arg| arg.to_string_lossy())
        .collect::<Vec<_>>()
        .join(" ")
}

struct FetchRefGuard<'a> {
    worktree: &'a Path,
    fetch_ref: &'a TemporaryRef,
}

impl Drop for FetchRefGuard<'_> {
    fn drop(&mut self) {
        let status = git_command()
            .arg("-C")
            .arg(self.worktree)
            .args(["update-ref", "-d", self.fetch_ref.as_str()])
            .status();
        match status {
            Ok(exit_status) if !exit_status.success() => warn!(
                "unable to remove temporary ref {}: git exited with {exit_status}",
                self.fetch_ref.as_str()
            ),
            Err(error) => warn!(
                "unable to remove temporary ref {}: {error}",
                self.fetch_ref.as_str()
            ),
            Ok(_) => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};
    use std::path::Path;

    use super::{
        BranchName, CommitId, ConfiguredRemote, SkipReason, WorktreeState,
        detect_concurrent_change, git_command, parse_default_branch,
    };

    #[test]
    fn parses_default_branch() {
        let branch = parse_default_branch("ref: refs/heads/master\tHEAD\nabc\tHEAD\n")
            .expect("parse ls-remote output")
            .expect("default branch exists");
        assert_eq!(branch.as_str(), "master");
    }

    #[test]
    fn ignores_unrelated_remote_refs() {
        assert_eq!(
            parse_default_branch("ref: refs/heads/topic\trefs/heads/topic\n")
                .expect("parse ls-remote output"),
            None
        );
    }

    #[test]
    fn reports_invalid_default_branch() {
        assert!(parse_default_branch("ref: refs/heads/invalid..branch\tHEAD\n").is_err());
    }

    #[test]
    fn detects_changed_origin_after_fetch() {
        let initial = worktree_state("file:///initial", '0', "master");
        let current = worktree_state("file:///changed", '0', "master");

        assert_eq!(
            detect_concurrent_change(&initial, &current, || -> Result<bool, ()> {
                panic!("local changes must not be inspected")
            }),
            Ok(Some(SkipReason::OriginChanged))
        );
    }

    #[test]
    fn detects_changed_head_after_fetch() {
        let initial = worktree_state("file:///remote", '0', "master");
        let current = worktree_state("file:///remote", '1', "master");

        assert_eq!(
            detect_concurrent_change(&initial, &current, || -> Result<bool, ()> {
                panic!("local changes must not be inspected")
            }),
            Ok(Some(SkipReason::HeadChanged))
        );
    }

    #[test]
    fn detects_changed_branch_after_fetch() {
        let initial = worktree_state("file:///remote", '0', "master");
        let current = worktree_state("file:///remote", '0', "topic");

        assert_eq!(
            detect_concurrent_change(&initial, &current, || -> Result<bool, ()> {
                panic!("local changes must not be inspected")
            }),
            Ok(Some(SkipReason::BranchChanged))
        );
    }

    #[test]
    fn detects_local_changes_after_fetch() {
        let initial = worktree_state("file:///remote", '0', "master");
        let current = worktree_state("file:///remote", '0', "master");

        assert_eq!(
            detect_concurrent_change(&initial, &current, || Ok::<_, ()>(true)),
            Ok(Some(SkipReason::LocalChangesDuringFetch))
        );
    }

    #[test]
    fn accepts_unchanged_worktree_after_fetch() {
        let initial = worktree_state("file:///remote", '0', "master");
        let current = worktree_state("file:///remote", '0', "master");

        assert_eq!(
            detect_concurrent_change(&initial, &current, || Ok::<_, ()>(false)),
            Ok(None)
        );
    }

    #[test]
    fn configures_git_for_non_interactive_network_access() {
        let command = git_command();
        let environment = command
            .get_envs()
            .filter_map(|(name, value)| {
                value.map(|value| (name.to_string_lossy(), value.to_string_lossy()))
            })
            .collect::<HashMap<_, _>>();
        let removed_environment = command
            .get_envs()
            .filter_map(|(name, value)| value.is_none().then(|| name.to_string_lossy()))
            .collect::<HashSet<_>>();

        assert_eq!(environment["GIT_TERMINAL_PROMPT"], "0");
        assert_eq!(environment["GIT_CONFIG_GLOBAL"], "/dev/null");
        assert_eq!(environment["GIT_CONFIG_NOSYSTEM"], "1");
        assert_eq!(environment["GIT_CONFIG_SYSTEM"], "/dev/null");
        assert_eq!(environment["GIT_ASKPASS"], "false");
        assert_eq!(environment["SSH_ASKPASS"], "false");
        assert!(environment["GIT_SSH_COMMAND"].contains("BatchMode=yes"));
        assert!(environment["GIT_SSH_COMMAND"].contains("ConnectTimeout=60"));
        assert_eq!(environment["GIT_HTTP_LOW_SPEED_LIMIT"], "1");
        assert_eq!(environment["GIT_HTTP_LOW_SPEED_TIME"], "60");
        for variable in [
            "GIT_ALTERNATE_OBJECT_DIRECTORIES",
            "GIT_CEILING_DIRECTORIES",
            "GIT_COMMON_DIR",
            "GIT_CONFIG",
            "GIT_CONFIG_COUNT",
            "GIT_CONFIG_PARAMETERS",
            "GIT_DIR",
            "GIT_DISCOVERY_ACROSS_FILESYSTEM",
            "GIT_EXEC_PATH",
            "GIT_GRAFT_FILE",
            "GIT_INDEX_FILE",
            "GIT_NAMESPACE",
            "GIT_OBJECT_DIRECTORY",
            "GIT_PROXY_COMMAND",
            "GIT_SHALLOW_FILE",
            "GIT_SSH_VARIANT",
            "GIT_TEMPLATE_DIR",
            "GIT_WORK_TREE",
        ] {
            assert!(removed_environment.contains(variable));
        }
        assert_eq!(command.get_current_dir(), Some(Path::new("/")));
    }

    fn worktree_state(origin: &str, head_digit: char, branch: &str) -> WorktreeState {
        WorktreeState {
            origin: Some(ConfiguredRemote::new(origin.to_owned())),
            head: CommitId::parse(&head_digit.to_string().repeat(40)).expect("valid commit ID"),
            branch: Some(BranchName::parse(branch.to_owned()).expect("valid branch name")),
        }
    }
}
