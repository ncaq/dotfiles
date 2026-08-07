use std::fmt::{self, Display};
use std::path::{Component, Path, PathBuf};
use std::str::FromStr;

use gix_hash::ObjectId;
use thiserror::Error;
use url::Url;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RemoteUrl {
    original: String,
    parsed: Url,
}

impl RemoteUrl {
    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.original
    }

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
pub enum RemoteUrlError {
    #[error(transparent)]
    Parse(#[from] url::ParseError),
    #[error("unsupported Git remote URL scheme `{0}`; expected https, ssh, or file")]
    UnsupportedScheme(String),
    #[error("Git remote URL must not contain a password")]
    Password,
    #[error("HTTPS and file Git remote URLs must not contain a username")]
    Username,
    #[error("Git remote URL must not contain whitespace or control characters")]
    UnsafeCharacter,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct WorktreePath(PathBuf);

impl WorktreePath {
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
pub enum WorktreePathError {
    #[error("worktree path must be absolute")]
    Relative,
    #[error("worktree path must not be the filesystem root")]
    Root,
    #[error("worktree path must not contain `.` or `..` components")]
    NotNormalized,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PartialCloneFilter(String);

impl PartialCloneFilter {
    #[must_use]
    pub fn git_argument(&self) -> String {
        format!("--filter={}", self.0)
    }

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
pub enum PartialCloneFilterError {
    #[error("partial clone filter must not be empty")]
    Empty,
    #[error("partial clone filter must not contain whitespace or NUL")]
    UnsafeCharacter,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct BranchName(String);

impl BranchName {
    pub fn parse(value: String) -> Result<Self, BranchNameError> {
        let full_name = format!("refs/heads/{value}");
        gix_validate::reference::branch_name(full_name.as_str().into())?;
        Ok(Self(value))
    }

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
pub struct BranchNameError(#[from] gix_validate::reference::name::Error);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CommitId(ObjectId);

impl CommitId {
    pub fn parse(value: &str) -> Result<Self, gix_hash::decode::Error> {
        ObjectId::from_hex(value.as_bytes()).map(Self)
    }
}

#[derive(Debug, Eq, PartialEq)]
pub struct ConfiguredRemote(String);

impl ConfiguredRemote {
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
