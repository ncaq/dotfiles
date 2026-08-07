use std::fmt::{self, Display};
use std::path::{Component, Path, PathBuf};
use std::str::FromStr;

use gix_hash::ObjectId;
use thiserror::Error;
use url::Url;

#[derive(Clone, Debug, Eq, PartialEq)]
/// A validated Git remote URL using the `https`, `ssh`, or `file` scheme.
///
/// The original spelling is retained for exact comparison with the URL stored by Git.
pub struct RemoteUrl {
    original: String,
    parsed: Url,
}

impl RemoteUrl {
    /// Returns the original validated URL string passed to Git.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.original
    }

    /// Returns the parsed URL representation.
    #[must_use]
    pub fn parsed(&self) -> &Url {
        &self.parsed
    }
}

impl Display for RemoteUrl {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.original.fmt(formatter)
    }
}

impl FromStr for RemoteUrl {
    type Err = RemoteUrlError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        if value.chars().any(char::is_whitespace) || value.chars().any(char::is_control) {
            return Err(RemoteUrlError::UnsafeCharacter);
        }
        let url = Url::parse(value)?;
        match url.scheme() {
            "https" | "ssh" | "file" => {}
            scheme => return Err(RemoteUrlError::UnsupportedScheme(scheme.to_owned())),
        }
        if url.password().is_some() {
            return Err(RemoteUrlError::Password);
        }
        if matches!(url.scheme(), "https" | "file") && !url.username().is_empty() {
            return Err(RemoteUrlError::Username);
        }
        Ok(Self {
            original: value.to_owned(),
            parsed: url,
        })
    }
}

#[derive(Debug, Error)]
/// An error produced while validating a Git remote URL.
pub enum RemoteUrlError {
    /// The value is not a syntactically valid URL.
    #[error(transparent)]
    Parse(#[from] url::ParseError),
    /// The URL uses a transport scheme unsupported by this tool.
    #[error("unsupported Git remote URL scheme `{0}`; expected https, ssh, or file")]
    UnsupportedScheme(String),
    /// The URL embeds a password.
    #[error("Git remote URL must not contain a password")]
    Password,
    /// An HTTPS or file URL embeds a username.
    #[error("HTTPS and file Git remote URLs must not contain a username")]
    Username,
    /// The URL contains whitespace or a control character.
    #[error("Git remote URL must not contain whitespace or control characters")]
    UnsafeCharacter,
}

#[derive(Clone, Debug, Eq, PartialEq)]
/// A normalized absolute path suitable as a Git worktree destination.
pub struct WorktreePath(PathBuf);

impl WorktreePath {
    /// Returns the validated filesystem path.
    #[must_use]
    pub fn as_path(&self) -> &Path {
        &self.0
    }
}

impl Display for WorktreePath {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.display().fmt(formatter)
    }
}

impl FromStr for WorktreePath {
    type Err = WorktreePathError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        Self::try_from(PathBuf::from(value))
    }
}

impl TryFrom<PathBuf> for WorktreePath {
    type Error = WorktreePathError;

    fn try_from(path: PathBuf) -> Result<Self, Self::Error> {
        if !path.is_absolute() {
            return Err(WorktreePathError::Relative);
        }
        if path == Path::new("/") {
            return Err(WorktreePathError::Root);
        }
        if path
            .components()
            .any(|component| matches!(component, Component::CurDir | Component::ParentDir))
        {
            return Err(WorktreePathError::NotNormalized);
        }
        Ok(Self(path))
    }
}

#[derive(Debug, Error)]
/// An error produced while validating a worktree path.
pub enum WorktreePathError {
    /// The path is relative.
    #[error("worktree path must be absolute")]
    Relative,
    /// The path refers to the filesystem root.
    #[error("worktree path must not be the filesystem root")]
    Root,
    /// The path contains a current-directory or parent-directory component.
    #[error("worktree path must not contain `.` or `..` components")]
    NotNormalized,
}

#[derive(Clone, Debug, Eq, PartialEq)]
/// A non-empty partial clone filter safe to pass as one Git argument.
///
/// Git validates the filter grammar. This type only guarantees that the value cannot be
/// split into additional command-line arguments.
pub struct PartialCloneFilter(String);

impl PartialCloneFilter {
    /// Returns the complete `--filter=<value>` argument for Git.
    #[must_use]
    pub fn git_argument(&self) -> String {
        format!("--filter={}", self.0)
    }

    /// Returns the filter specification without the `--filter=` prefix.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Display for PartialCloneFilter {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

impl FromStr for PartialCloneFilter {
    type Err = PartialCloneFilterError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        if value.is_empty() {
            return Err(PartialCloneFilterError::Empty);
        }
        if value.chars().any(char::is_whitespace) || value.contains('\0') {
            return Err(PartialCloneFilterError::UnsafeCharacter);
        }
        Ok(Self(value.to_owned()))
    }
}

#[derive(Debug, Error)]
/// An error produced while validating a partial clone filter argument.
pub enum PartialCloneFilterError {
    /// The filter is empty.
    #[error("partial clone filter must not be empty")]
    Empty,
    /// The filter contains characters that would make it unsafe as one argument.
    #[error("partial clone filter must not contain whitespace or NUL")]
    UnsafeCharacter,
}

#[derive(Clone, Debug, Eq, PartialEq)]
/// A short local branch name validated according to Git's reference rules.
pub struct BranchName(String);

impl BranchName {
    /// Validates and constructs a short local branch name.
    pub fn parse(value: String) -> Result<Self, BranchNameError> {
        let full_name = format!("refs/heads/{value}");
        gix_validate::reference::branch_name(full_name.as_str().into())?;
        Ok(Self(value))
    }

    /// Returns the short branch name.
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl FromStr for BranchName {
    type Err = BranchNameError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        Self::parse(value.to_owned())
    }
}

impl Display for BranchName {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

#[derive(Debug, Error)]
#[error("invalid branch name: {0}")]
/// An error produced while validating a branch name.
pub struct BranchNameError(#[from] gix_validate::reference::name::Error);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
/// A complete SHA-1 or SHA-256 Git object ID.
pub struct CommitId(ObjectId);

impl CommitId {
    /// Parses a full hexadecimal Git object ID.
    pub fn parse(value: &str) -> Result<Self, gix_hash::decode::Error> {
        ObjectId::from_hex(value.as_bytes()).map(Self)
    }
}

#[derive(Debug, Eq, PartialEq)]
/// The opaque remote location read from an existing Git configuration.
pub struct ConfiguredRemote(String);

impl ConfiguredRemote {
    /// Wraps a remote location returned by Git without changing its spelling.
    #[must_use]
    pub fn new(value: String) -> Self {
        Self(value)
    }
}

impl Display for ConfiguredRemote {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(formatter)
    }
}

impl PartialEq<RemoteUrl> for ConfiguredRemote {
    fn eq(&self, other: &RemoteUrl) -> bool {
        self.0 == other.as_str()
    }
}

#[derive(Debug)]
pub(crate) struct TemporaryRef(String);

impl TemporaryRef {
    #[must_use]
    pub fn for_current_process() -> Self {
        Self(format!("refs/git-repo-subscribe/{}", std::process::id()))
    }

    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}
