mod domain;

use std::ffi::{OsStr, OsString};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Output, Stdio};

use log::warn;
use thiserror::Error;

pub use domain::{BranchName, ConfiguredRemote, PartialCloneFilter, RemoteUrl, WorktreePath};
use domain::{CommitId, TemporaryRef};

#[derive(Debug)]
pub struct Repository {
    remote: RemoteUrl,
    worktree: WorktreePath,
    partial_clone_filter: PartialCloneFilter,
}

impl Repository {
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

    #[must_use]
    pub fn remote(&self) -> &RemoteUrl {
        &self.remote
    }

    #[must_use]
    pub fn worktree(&self) -> &WorktreePath {
        &self.worktree
    }

    #[must_use]
    pub fn partial_clone_filter(&self) -> &PartialCloneFilter {
        &self.partial_clone_filter
    }
}

#[derive(Debug, Eq, PartialEq)]
pub enum Outcome {
    Cloned,
    Updated,
    Skipped(SkipReason),
}

#[derive(Debug, Eq, PartialEq)]
pub enum SkipReason {
    NotWorktree,
    NotWorktreeRoot,
    NoOrigin,
    OriginMismatch {
        actual: ConfiguredRemote,
    },
    LocalChanges,
    DetachedHead,
    RemoteUnavailable,
    DefaultBranchUnknown,
    NotDefaultBranch {
        current: BranchName,
        default: BranchName,
    },
    FetchFailed,
    OriginChanged,
    HeadChanged,
    BranchChanged,
    LocalChangesDuringFetch,
    FastForwardFailed,
}

impl SkipReason {
    #[must_use]
    pub fn warning(&self, repository: &Repository) -> String {
        let path = repository.worktree();
        match self {
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
pub enum SubscribeError {
    #[error("failed to create {}: {source}", .path.display())]
    CreateParent {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("failed to run git {}: {source}", display_args(.args))]
    RunGit {
        args: Vec<OsString>,
        source: std::io::Error,
    },
    #[error("git {} failed with {status}", display_args(.args))]
    GitFailed {
        args: Vec<OsString>,
        status: ExitStatus,
    },
    #[error("git {} returned non-UTF-8 output: {source}", display_args(.args))]
    InvalidGitOutput {
        args: Vec<OsString>,
        source: std::string::FromUtf8Error,
    },
    #[error("failed to resolve {}: {source}", .path.display())]
    Canonicalize {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("Git returned an invalid branch name: {0}")]
    InvalidBranch(#[from] domain::BranchNameError),
    #[error("Git returned an invalid commit ID: {0}")]
    InvalidCommitId(#[from] gix_hash::decode::Error),
}

impl SubscribeError {
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

    #[must_use]
    pub fn is_git_failure(&self) -> bool {
        matches!(self, Self::GitFailed { .. })
    }
}

pub fn subscribe(repository: &Repository) -> Result<Outcome, SubscribeError> {
    let worktree = repository.worktree().as_path();
    if !worktree.exists() {
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

    if !git_status_in(worktree, ["rev-parse", "--is-inside-work-tree"], true)? {
        return Ok(Outcome::Skipped(SkipReason::NotWorktree));
    }

    let worktree_root = git_text_in(worktree, ["rev-parse", "--show-toplevel"])?;
    if canonicalize(worktree)? != canonicalize(Path::new(&worktree_root))? {
        return Ok(Outcome::Skipped(SkipReason::NotWorktreeRoot));
    }

    let Some(origin_url) = git_optional_text_in(worktree, ["remote", "get-url", "origin"])? else {
        return Ok(Outcome::Skipped(SkipReason::NoOrigin));
    };
    let origin_url = ConfiguredRemote::new(origin_url);
    if origin_url != *repository.remote() {
        return Ok(Outcome::Skipped(SkipReason::OriginMismatch {
            actual: origin_url,
        }));
    }

    if has_local_changes(worktree)? {
        return Ok(Outcome::Skipped(SkipReason::LocalChanges));
    }

    let Some(initial_branch) = current_branch(worktree)? else {
        return Ok(Outcome::Skipped(SkipReason::DetachedHead));
    };

    let remote_head = match git_output([
        "ls-remote",
        "--symref",
        "--",
        repository.remote().as_str(),
        "HEAD",
    ])? {
        output if output.status.success() => output,
        _ => return Ok(Outcome::Skipped(SkipReason::RemoteUnavailable)),
    };
    let remote_head = output_text(
        [
            "ls-remote",
            "--symref",
            "--",
            repository.remote().as_str(),
            "HEAD",
        ],
        remote_head.stdout,
    )?;
    let Some(default_branch) = parse_default_branch(&remote_head)? else {
        return Ok(Outcome::Skipped(SkipReason::DefaultBranchUnknown));
    };
    if initial_branch != default_branch {
        return Ok(Outcome::Skipped(SkipReason::NotDefaultBranch {
            current: initial_branch,
            default: default_branch,
        }));
    }

    let head = head_id(worktree)?;
    let fetch_ref = TemporaryRef::for_current_process();
    let _fetch_ref_guard = FetchRefGuard {
        worktree,
        fetch_ref: &fetch_ref,
    };
    let refspec = format!("+{}:{}", default_branch.as_str(), fetch_ref.as_str());
    if !git_status_in(
        worktree,
        ["fetch", "--no-write-fetch-head", "origin", &refspec],
        false,
    )? {
        return Ok(Outcome::Skipped(SkipReason::FetchFailed));
    }

    if git_optional_text_in(worktree, ["remote", "get-url", "origin"])?
        .map(ConfiguredRemote::new)
        .as_ref()
        != Some(&origin_url)
    {
        return Ok(Outcome::Skipped(SkipReason::OriginChanged));
    }
    if optional_head_id(worktree)? != Some(head) {
        return Ok(Outcome::Skipped(SkipReason::HeadChanged));
    }
    if current_branch(worktree)?.as_ref() != Some(&initial_branch) {
        return Ok(Outcome::Skipped(SkipReason::BranchChanged));
    }
    if has_local_changes(worktree)? {
        return Ok(Outcome::Skipped(SkipReason::LocalChangesDuringFetch));
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
        ["status", "--porcelain=v1", "--untracked-files=normal"],
    )?
    .is_empty())
}

fn current_branch(path: &Path) -> Result<Option<BranchName>, SubscribeError> {
    git_optional_text_in(path, ["symbolic-ref", "--quiet", "--short", "HEAD"])?
        .map(BranchName::parse)
        .transpose()
        .map_err(Into::into)
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
    git_optional_text_in(path, ["rev-parse", "HEAD"])?
        .map(|value| CommitId::parse(&value))
        .transpose()
        .map_err(Into::into)
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

fn git_status_in<I, S>(path: &Path, args: I, quiet: bool) -> Result<bool, SubscribeError>
where
    I: IntoIterator<Item = S> + Clone,
    S: AsRef<OsStr>,
{
    let collected = collect_args(args.clone());
    let mut command = Command::new("git");
    command.arg("-C").arg(path).args(&collected);
    if quiet {
        command.stdout(std::process::Stdio::null());
        command.stderr(std::process::Stdio::null());
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
    let status = Command::new("git")
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
    let output = Command::new("git")
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
    Command::new("git")
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
        let status = Command::new("git")
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
    use super::parse_default_branch;

    #[test]
    fn parses_default_branch() {
        let branch = parse_default_branch("ref: refs/heads/master\tHEAD\nabc\tHEAD\n")
            .expect("parse ls-remote output")
            .expect("default branch exists");
        assert_eq!(branch.as_str(), "master");
    }
}
