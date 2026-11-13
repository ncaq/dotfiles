/**
 * `renovate-recovery`ワークフローの`recover`ジョブで、Claude Codeが終わった後に動く処理の本体。
 *
 * `claude-code-action`が残した実行の記録を読んで、
 * 中身を含まない要約をジョブのログに出します。
 * `actions/github-script`から呼ばれます。
 *
 * 以下の環境変数を読みます。
 *
 * - `EXECUTION_FILE`: 実行の記録のファイルのフルパス。空なら警告だけを出して要約を省略する
 */

import { readFile } from "node:fs/promises";
import process from "node:process";
import { summarizeExecution } from "./execution-summary.ts";
import type { ScriptArguments } from "./script-arguments.ts";

/** 要約の出力先。`@actions/core`のうち使う分だけです。 */
export interface SummaryReporter {
  info(message: string): void;
  warning(message: string): void;
}

/**
 * 実行の記録の要約を出します。
 *
 * 要約は調査のための補助なので、読めなくても警告に留めて例外を投げません。
 * 例外で終わると、復旧そのものは済んでいるのにジョブが失敗して見えてしまうからです。
 */
export async function reportExecutionFile(
  reporter: SummaryReporter,
  file: string | undefined,
): Promise<void> {
  if (file == null || file === "") {
    reporter.warning("実行の記録のファイルが渡されていないので、要約を省略します");
    return;
  }
  try {
    const execution: unknown = JSON.parse(await readFile(file, "utf8"));
    for (const line of summarizeExecution(execution)) {
      reporter.info(line);
    }
  } catch (error) {
    reporter.warning(
      `実行の記録を読めませんでした: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

export async function reportExecution({ core }: ScriptArguments): Promise<void> {
  await reportExecutionFile(core, process.env["EXECUTION_FILE"]);
}
