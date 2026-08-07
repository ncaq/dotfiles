use std::path::PathBuf;
use std::process::ExitCode;

use git_repo_subscribe::{Outcome, Repository, subscribe};

fn main() -> ExitCode {
    let mut args = std::env::args();
    let _program = args.next();
    let (Some(url), Some(path), Some(partial_clone_filter), None) =
        (args.next(), args.next(), args.next(), args.next())
    else {
        eprintln!("Usage: git-repo-subscribe URL PATH FILTER");
        return ExitCode::from(2);
    };

    let repository = Repository {
        url,
        path: PathBuf::from(path),
        partial_clone_filter,
    };
    match subscribe(&repository) {
        Ok(Outcome::Skipped(reason)) => {
            eprintln!("Warning: {}", reason.warning(&repository));
            ExitCode::SUCCESS
        }
        Ok(Outcome::Cloned | Outcome::Updated) => ExitCode::SUCCESS,
        Err(error) => {
            if !error.is_git_failure() {
                eprintln!("Error: {error}");
            }
            ExitCode::from(error.exit_code())
        }
    }
}
