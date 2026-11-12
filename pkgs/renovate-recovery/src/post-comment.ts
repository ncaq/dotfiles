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

import { constants } from "node:fs";
import { lstat, open } from "node:fs/promises";
import { buildCommentBody } from "./comment.ts";
import { requireEnv, requireIntegerEnv } from "./env.ts";
import { rejectResultDir, rejectResultFile } from "./recovery-output.ts";
import type { ActionsCore, ScriptArguments } from "./script-arguments.ts";

/** 例外が指定したエラーコードのものかを判定します。 */
function hasErrorCode(error: unknown, code: string): boolean {
  return error instanceof Error && "code" in error && error.code === code;
}

/** 読まなかった理由を警告に出して、結果の代わりに投稿する文を返します。 */
function rejected(reason: string, core: ActionsCore): string {
  core.warning(reason);
  return `${reason}。結果は読み込んでいません。`;
}

/**
 * 結果のファイルを読みます。
 * Claude Codeが書かずに終了した時は`undefined`を返します。
 * シンボリックリンクなど読んではいけないファイルの時は、読まずに理由を結果の代わりに返します。
 *
 * 調べてから開き直すと、その間に差し替えられるおそれがあるので、
 * リンクをたどらずに開いたハンドルを調べて、同じハンドルから読みます。
 */
async function readResult(
  file: string,
  resultDir: string,
  core: ActionsCore,
): Promise<string | undefined> {
  try {
    const dirRejection = rejectResultDir({ isDirectory: (await lstat(resultDir)).isDirectory() });
    if (dirRejection != null) {
      return rejected(dirRejection, core);
    }
  } catch (error) {
    if (hasErrorCode(error, "ENOENT")) {
      return undefined;
    }
    throw error;
  }

  let handle;
  try {
    handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  } catch (error) {
    if (hasErrorCode(error, "ENOENT")) {
      return undefined;
    }
    if (hasErrorCode(error, "ELOOP")) {
      return rejected("結果のファイルがシンボリックリンクです", core);
    }
    throw error;
  }
  try {
    const stats = await handle.stat();
    const fileRejection = rejectResultFile({
      isFile: stats.isFile(),
      nlink: stats.nlink,
      size: stats.size,
    });
    if (fileRejection != null) {
      return rejected(fileRejection, core);
    }
    return await handle.readFile({ encoding: "utf8" });
  } finally {
    await handle.close();
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
