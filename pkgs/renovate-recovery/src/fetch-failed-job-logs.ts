/**
 * `renovate-recovery`ワークフローの`recover`ジョブで、Claude Codeを起動する前に動く処理の本体。
 *
 * 失敗したワークフローの実行から失敗したジョブのログを取得して、
 * Claude Codeが読める作業ツリーの中のディレクトリへ保存します。
 * `actions/github-script`から呼ばれます。
 *
 * `check`から呼ばれた時はこのジョブ自身が同じ実行の中で動いていて、
 * 実行がまだ完了していません。
 * `gh run view --log`は実行が完了していないとログを返さないので、
 * 完了しているジョブ単位のログをAPIから取得します。
 * Claude Codeに任意のジョブのログを取得するAPIを許可しなくて済むよう、ワークフローの側で取得します。
 *
 * GitHubのクライアントの他に、以下の環境変数を読みます。
 *
 * - `RUN_ID`: 失敗したワークフローの実行のID。空なら何もしない
 * - `LOG_DIR`: ログを保存するディレクトリ
 */

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import type { JobSummary } from "./job-log.ts";
import { jobLogFileName, parseRunId, selectFailedJobs } from "./job-log.ts";
import type { ScriptArguments } from "./script-arguments.ts";

/** ログの取得に使うGitHubの操作。テストで偽物に差し替えられるよう、必要な分だけに絞ります。 */
export interface JobLogSource {
  /** 実行の最新の試行のジョブの一覧を返します。 */
  listJobs(runId: number): Promise<readonly JobSummary[]>;
  /** ジョブのログの本文を返します。 */
  downloadLog(jobId: number): Promise<string>;
}

/** 進み具合を伝える出力先。`@actions/core`のうち使う分だけです。 */
export interface LogReporter {
  info(message: string): void;
  warning(message: string): void;
}

/** 保存の処理への入力。 */
export interface SaveFailedJobLogsInput {
  /** 環境変数で渡された実行のID。 */
  readonly runId: string | undefined;
  /** ログを保存するディレクトリ。 */
  readonly logDir: string | undefined;
}

/** 例外を警告に載せる文字列にします。 */
function describeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * 失敗したジョブのログを保存します。
 *
 * ログは復旧を助ける補助なので、取得や保存に失敗しても警告に留めて例外を投げません。
 * 例外で終わるとClaude Codeが起動されないまま、処理済みとして記録されてしまうからです。
 */
export async function saveFailedJobLogs(
  source: JobLogSource,
  reporter: LogReporter,
  input: SaveFailedJobLogsInput,
): Promise<void> {
  const parsedRunId = parseRunId(input.runId);
  switch (parsedRunId.kind) {
    case "absent":
      // 手動実行で実行のIDが渡されていない時は、
      // 対象の実行は完了しているのでClaude Codeが`gh run view --log-failed`で読めます。
      reporter.info("実行のIDが渡されていないので、ログの取得を省略します");
      return;
    case "invalid":
      reporter.warning("実行のIDが正の整数ではないので、ログの取得を省略します");
      return;
    case "ok":
      break;
  }
  const { runId } = parsedRunId;
  const logDir = input.logDir;
  if (logDir == null || logDir === "") {
    reporter.warning("ログを保存するディレクトリが渡されていないので、ログの取得を省略します");
    return;
  }

  let failedJobs;
  try {
    await mkdir(logDir, { recursive: true });
    failedJobs = selectFailedJobs(await source.listJobs(runId));
  } catch (error) {
    reporter.warning(`実行${runId}のログを保存する準備に失敗しました: ${describeError(error)}`);
    return;
  }
  if (failedJobs.length === 0) {
    reporter.warning(`実行${runId}に失敗したジョブが見つかりませんでした`);
    return;
  }
  for (const job of failedJobs) {
    try {
      const file = path.join(logDir, jobLogFileName(job));
      await writeFile(file, await source.downloadLog(job.id), "utf8");
      reporter.info(`${job.name}のログを${file}へ保存しました`);
    } catch (error) {
      reporter.warning(`${job.name}のログを保存できませんでした: ${describeError(error)}`);
    }
  }
}

export async function fetchFailedJobLogs({
  github,
  context,
  core,
}: ScriptArguments): Promise<void> {
  const { owner, repo } = context.repo;
  const source: JobLogSource = {
    listJobs: (runId) =>
      github.paginate(github.rest.actions.listJobsForWorkflowRun, {
        owner,
        repo,
        run_id: runId,
        filter: "latest",
        per_page: 100,
      }),
    downloadLog: async (jobId) =>
      String(
        (await github.rest.actions.downloadJobLogsForWorkflowRun({ owner, repo, job_id: jobId }))
          .data,
      ),
  };
  await saveFailedJobLogs(source, core, {
    runId: process.env["RUN_ID"],
    logDir: process.env["LOG_DIR"],
  });
}
