use std::ffi::{OsStr, OsString};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Output, Stdio};

use log::warn;
use thiserror::Error;

#[derive(Debug)]
pub struct Repository {
    pub url: String,
    pub path: PathBuf,
    pub partial_clone_filter: String,
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
    OriginMismatch { actual: String },
    LocalChanges,
    DetachedHead,
    RemoteUnavailable,
    DefaultBranchUnknown,
    NotDefaultBranch { current: String, default: String },
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
        let path = repository.path.display();
        match self {
            Self::NotWorktree => format!("{path} is not a Git worktree; skipping update."),
            Self::NotWorktreeRoot => {
                format!("{path} is not the root of its Git worktree; skipping update.")
            }
            Self::NoOrigin => format!("{path} has no origin remote; skipping update."),
            Self::OriginMismatch { actual } => format!(
                "origin URL of {path} is {actual}, expected {}; skipping update.",
                repository.url
            ),
            Self::LocalChanges => format!("{path} has local changes; skipping update."),
            Self::DetachedHead => format!("{path} has a detached HEAD; skipping update."),
            Self::RemoteUnavailable => format!(
                "unable to query the default branch of {}; skipping update.",
                repository.url
            ),
            Self::DefaultBranchUnknown => format!(
                "unable to determine the default branch of {}; skipping update.",
                repository.url
            ),
            Self::NotDefaultBranch { current, default } => format!(
                "{path} is on {current}, not the default branch {default}; skipping update."
            ),
            Self::FetchFailed => {
                format!("unable to fetch {}; skipping update.", repository.url)
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
    if !repository.path.exists() {
        if let Some(parent) = repository.path.parent()
            && !parent.as_os_str().is_empty()
        {
            fs::create_dir_all(parent).map_err(|source| SubscribeError::CreateParent {
                path: parent.to_path_buf(),
                source,
            })?;
        }
        git_status_checked([
            OsStr::new("clone"),
            OsStr::new(&format!("--filter={}", repository.partial_clone_filter)),
            OsStr::new("--single-branch"),
            OsStr::new("--"),
            OsStr::new(&repository.url),
            repository.path.as_os_str(),
        ])?;
        return Ok(Outcome::Cloned);
    }

    if !git_status_in(
        &repository.path,
        ["rev-parse", "--is-inside-work-tree"],
        true,
    )? {
        return Ok(Outcome::Skipped(SkipReason::NotWorktree));
    }

    let worktree_root = git_text_in(&repository.path, ["rev-parse", "--show-toplevel"])?;
    if canonicalize(&repository.path)? != canonicalize(Path::new(&worktree_root))? {
        return Ok(Outcome::Skipped(SkipReason::NotWorktreeRoot));
    }

    let Some(origin_url) = git_optional_text_in(&repository.path, ["remote", "get-url", "origin"])?
    else {
        return Ok(Outcome::Skipped(SkipReason::NoOrigin));
    };
    if origin_url != repository.url {
        return Ok(Outcome::Skipped(SkipReason::OriginMismatch {
            actual: origin_url,
        }));
    }

    if has_local_changes(&repository.path)? {
        return Ok(Outcome::Skipped(SkipReason::LocalChanges));
    }

    let Some(initial_branch) = current_branch(&repository.path)? else {
        return Ok(Outcome::Skipped(SkipReason::DetachedHead));
    };

    let remote_head = match git_output(["ls-remote", "--symref", "--", &repository.url, "HEAD"])? {
        output if output.status.success() => output,
        _ => return Ok(Outcome::Skipped(SkipReason::RemoteUnavailable)),
    };
    let remote_head = output_text(
        ["ls-remote", "--symref", "--", &repository.url, "HEAD"],
        remote_head.stdout,
    )?;
    let Some(default_branch) = parse_default_branch(&remote_head) else {
        return Ok(Outcome::Skipped(SkipReason::DefaultBranchUnknown));
    };
    if initial_branch != default_branch {
        return Ok(Outcome::Skipped(SkipReason::NotDefaultBranch {
            current: initial_branch,
            default: default_branch,
        }));
    }

    let head = git_text_in(&repository.path, ["rev-parse", "HEAD"])?;
    let fetch_ref = format!("refs/git-repo-subscribe/{}", std::process::id());
    let _fetch_ref_guard = FetchRefGuard {
        worktree: &repository.path,
        fetch_ref: &fetch_ref,
    };
    let refspec = format!("+{default_branch}:{fetch_ref}");
    if !git_status_in(
        &repository.path,
        ["fetch", "--no-write-fetch-head", "origin", &refspec],
        false,
    )? {
        return Ok(Outcome::Skipped(SkipReason::FetchFailed));
    }

    if git_optional_text_in(&repository.path, ["remote", "get-url", "origin"])?.as_deref()
        != Some(origin_url.as_str())
    {
        return Ok(Outcome::Skipped(SkipReason::OriginChanged));
    }
    if git_optional_text_in(&repository.path, ["rev-parse", "HEAD"])?.as_deref()
        != Some(head.as_str())
    {
        return Ok(Outcome::Skipped(SkipReason::HeadChanged));
    }
    if current_branch(&repository.path)?.as_deref() != Some(initial_branch.as_str()) {
        return Ok(Outcome::Skipped(SkipReason::BranchChanged));
    }
    if has_local_changes(&repository.path)? {
        return Ok(Outcome::Skipped(SkipReason::LocalChangesDuringFetch));
    }
    if !git_status_in(
        &repository.path,
        ["merge", "--ff-only", "--no-overwrite-ignore", &fetch_ref],
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

fn current_branch(path: &Path) -> Result<Option<String>, SubscribeError> {
    git_optional_text_in(path, ["symbolic-ref", "--quiet", "--short", "HEAD"])
}

fn parse_default_branch(remote_head: &str) -> Option<String> {
    remote_head.lines().find_map(|line| {
        line.strip_prefix("ref: refs/heads/")
            .and_then(|value| value.strip_suffix("\tHEAD"))
            .map(ToOwned::to_owned)
    })
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
    fetch_ref: &'a str,
}

impl Drop for FetchRefGuard<'_> {
    fn drop(&mut self) {
        let status = Command::new("git")
            .arg("-C")
            .arg(self.worktree)
            .args(["update-ref", "-d", self.fetch_ref])
            .status();
        match status {
            Ok(exit_status) if !exit_status.success() => warn!(
                "unable to remove temporary ref {}: git exited with {exit_status}",
                self.fetch_ref
            ),
            Err(error) => warn!("unable to remove temporary ref {}: {error}", self.fetch_ref),
            Ok(_) => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::parse_default_branch;

    #[test]
    fn parses_default_branch() {
        assert_eq!(
            parse_default_branch("ref: refs/heads/master\tHEAD\nabc\tHEAD\n"),
            Some("master".to_owned())
        );
    }
}
