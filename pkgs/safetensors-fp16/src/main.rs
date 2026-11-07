use std::path::PathBuf;

use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(about = "safetensorsのF32テンソルだけをF16へ変換する。")]
struct Args {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// 変換してdstへ書き出す。
    Convert {
        /// 変換元のsafetensorsファイル。
        src: PathBuf,
        /// 書き出し先のパス。
        dst: PathBuf,
        /// fp16の範囲を超える重みがinfになることを許容する。
        #[arg(long)]
        allow_overflow: bool,
    },
    /// 変換結果をsrcと突き合わせる。
    Verify {
        /// 変換元のsafetensorsファイル。
        src: PathBuf,
        /// 検証するsafetensorsファイル。
        dst: PathBuf,
    },
}

fn main() -> Result<()> {
    match Args::parse().command {
        Command::Convert {
            src,
            dst,
            allow_overflow,
        } => safetensors_fp16::convert(&src, &dst, allow_overflow),
        Command::Verify { src, dst } => safetensors_fp16::verify(&src, &dst),
    }
}
