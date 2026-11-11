/**
 * `renovate-recovery`ワークフローの`recover`ジョブの最後に動く処理の本体。
 *
 * Claude Codeが書いた結果を、処理済みの目印をつけてRenovateのPRへコメントします。
 * `actions/github-script`から呼ばれます。
 *
 * GitHubのクライアントの他に、以下の環境変数を読みます。
 *
 * - `PR_NUMBER`: RenovateのPRの番号
 * - `KEY`: `gate`ジョブが出力した更新の内容のキー
 * - `RESULT_FILE`: Claude Codeが結果を書くファイル。無くてもよい
 */

import { readFile } from "node:fs/promises";
import { buildCommentBody } from "./comment.ts";
import { requireEnv, requireIntegerEnv } from "./env.ts";
import type { ScriptArguments } from "./script-arguments.ts";

/** 結果のファイルを読みます。Claude Codeが書かずに終了した時は`undefined`を返します。 */
async function readResult(path: string): Promise<string | undefined> {
  try {
    return await readFile(path, "utf8");
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") {
      return undefined;
    }
    throw error;
  }
}

export async function postComment({ github, context }: ScriptArguments): Promise<void> {
  const { owner, repo } = context.repo;
  const body = buildCommentBody({
    key: requireEnv("KEY"),
    result: await readResult(requireEnv("RESULT_FILE")),
    runUrl: `${context.serverUrl}/${owner}/${repo}/actions/runs/${context.runId}`,
  });
  await github.rest.issues.createComment({
    owner,
    repo,
    issue_number: requireIntegerEnv("PR_NUMBER"),
    body,
  });
}
