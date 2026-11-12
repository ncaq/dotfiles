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
 * - `RESULT_DIR`: 結果のファイルを置いてよいディレクトリ
 */

import { lstat, readFile, realpath } from "node:fs/promises";
import { buildCommentBody } from "./comment.ts";
import { requireEnv, requireIntegerEnv } from "./env.ts";
import { rejectResultFile } from "./recovery-output.ts";
import type { ActionsCore, ScriptArguments } from "./script-arguments.ts";

/** ファイルが存在しない時のエラーかを判定します。 */
function isNotFound(error: unknown): boolean {
  return error instanceof Error && "code" in error && error.code === "ENOENT";
}

/**
 * 結果のファイルを読みます。
 * Claude Codeが書かずに終了した時は`undefined`を返します。
 * シンボリックリンクなど読んではいけないファイルの時は、読まずに理由を結果の代わりに返します。
 */
async function readResult(
  file: string,
  allowedDir: string,
  core: ActionsCore,
): Promise<string | undefined> {
  try {
    const stats = await lstat(file);
    const rejection = rejectResultFile(
      { isRegularFile: stats.isFile(), realPath: await realpath(file), size: stats.size },
      await realpath(allowedDir),
    );
    if (rejection != null) {
      core.warning(rejection);
      return `${rejection}。結果は読み込んでいません。`;
    }
    return await readFile(file, "utf8");
  } catch (error) {
    if (isNotFound(error)) {
      return undefined;
    }
    throw error;
  }
}

export async function postComment({ github, context, core }: ScriptArguments): Promise<void> {
  const { owner, repo } = context.repo;
  const body = buildCommentBody({
    key: requireEnv("KEY"),
    result: await readResult(requireEnv("RESULT_FILE"), requireEnv("RESULT_DIR"), core),
    runUrl: `${context.serverUrl}/${owner}/${repo}/actions/runs/${context.runId}`,
  });
  await github.rest.issues.createComment({
    owner,
    repo,
    issue_number: requireIntegerEnv("PR_NUMBER"),
    body,
  });
}
