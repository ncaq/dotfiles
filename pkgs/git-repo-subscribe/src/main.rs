use std::process::ExitCode;

use clap::Parser;
use git_repo_subscribe::{
    Outcome, PartialCloneFilter, RemoteUrl, Repository, WorktreePath, subscribe,
};
use log::{error, warn};

#[derive(Parser)]
#[command(about = "Clone and safely update a Git repository")]
struct Args {
    #[arg(value_name = "URL")]
    remote: RemoteUrl,

    #[arg(value_name = "PATH")]
    worktree: WorktreePath,

    #[arg(value_name = "FILTER", allow_hyphen_values = true)]
    partial_clone_filter: PartialCloneFilter,
}

fn main() -> ExitCode {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn")).init();

    let args = Args::parse();
    let repository = Repository::new(args.remote, args.worktree, args.partial_clone_filter);
    match subscribe(&repository) {
        Ok(Outcome::Skipped(reason)) => {
            warn!("{}", reason.warning(&repository));
            ExitCode::SUCCESS
        }
        Ok(Outcome::Cloned | Outcome::Updated) => ExitCode::SUCCESS,
        Err(error) => {
            if !error.is_git_failure() {
                error!("{error}");
            }
            ExitCode::from(error.exit_code())
        }
    }
}
