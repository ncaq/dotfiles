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
import { requireEnv } from "./env.ts";
import { jobLogFileName, parseRunId, selectFailedJobs } from "./job-log.ts";
import type { ScriptArguments } from "./script-arguments.ts";

/** 例外を警告に載せる文字列にします。 */
function describeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * ログは復旧を助ける補助なので、取得に失敗しても警告に留めて、このステップ自体は成功させます。
 * ステップが失敗するとClaude Codeが起動されないまま、処理済みとして記録されてしまうからです。
 */
export async function fetchFailedJobLogs({
  github,
  context,
  core,
}: ScriptArguments): Promise<void> {
  const runId = parseRunId(process.env["RUN_ID"]);
  if (runId === undefined) {
    // 手動実行で実行のIDが渡されていない時は、
    // 対象の実行は完了しているのでClaude Codeが`gh run view --log-failed`で読めます。
    core.info("実行のIDが渡されていないので、ログの取得を省略します");
    return;
  }
  if (runId === null) {
    core.warning("実行のIDが正の整数ではないので、ログの取得を省略します");
    return;
  }
  const { owner, repo } = context.repo;
  const logDir = requireEnv("LOG_DIR");
  await mkdir(logDir, { recursive: true });

  let failedJobs;
  try {
    const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRun, {
      owner,
      repo,
      run_id: runId,
      filter: "latest",
      per_page: 100,
    });
    failedJobs = selectFailedJobs(jobs);
  } catch (error) {
    core.warning(`実行${runId}のジョブの一覧を取得できませんでした: ${describeError(error)}`);
    return;
  }
  if (failedJobs.length === 0) {
    core.warning(`実行${runId}に失敗したジョブが見つかりませんでした`);
    return;
  }
  for (const job of failedJobs) {
    try {
      const response = await github.rest.actions.downloadJobLogsForWorkflowRun({
        owner,
        repo,
        job_id: job.id,
      });
      const file = path.join(logDir, jobLogFileName(job));
      await writeFile(file, String(response.data), "utf8");
      core.info(`${job.name}のログを${file}へ保存しました`);
    } catch (error) {
      core.warning(`${job.name}のログを保存できませんでした: ${describeError(error)}`);
    }
  }
}
