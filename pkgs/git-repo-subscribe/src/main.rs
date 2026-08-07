use std::path::PathBuf;
use std::process::ExitCode;

use clap::Parser;
use git_repo_subscribe::{Outcome, Repository, subscribe};
use log::{error, warn};

#[derive(Parser)]
#[command(about = "Clone and safely update a Git repository")]
struct Args {
    #[arg(value_name = "URL")]
    url: String,

    #[arg(value_name = "PATH")]
    path: PathBuf,

    #[arg(value_name = "FILTER")]
    partial_clone_filter: String,
}

fn main() -> ExitCode {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn")).init();

    let args = Args::parse();
    let repository = Repository {
        url: args.url,
        path: args.path,
        partial_clone_filter: args.partial_clone_filter,
    };
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
