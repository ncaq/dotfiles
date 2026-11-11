/**
 * `renovate-recovery`ワークフローの`gate`ジョブの本体。
 *
 * Claude Codeを起動するかどうかを決めて、ジョブの出力へ書きます。
 * `actions/github-script`から呼ばれます。
 *
 * GitHubのクライアントの他に、以下の環境変数を読みます。
 *
 * - `PR_NUMBER`: 復旧の対象にするRenovateのPRの番号
 * - `FORCE`: `true`なら抑止の条件を無視する
 * - `COOLDOWN_HOURS`: 同じPRに対して次に動かすまで空ける時間
 */

import process from "node:process";
import { parseRecoveryRecords } from "./comment.ts";
import { decide, recoveryBranch, updateKey } from "./decide.ts";
import { requireIntegerEnv } from "./env.ts";
import type { ScriptArguments } from "./script-arguments.ts";

export async function gate({ github, context, core }: ScriptArguments): Promise<void> {
  const { owner, repo } = context.repo;
  const pullNumber = requireIntegerEnv("PR_NUMBER");
  const cooldownHours = requireIntegerEnv("COOLDOWN_HOURS");

  const [pull, files, comments, recoveryPulls] = await Promise.all([
    github.rest.pulls.get({ owner, repo, pull_number: pullNumber }),
    github.paginate(github.rest.pulls.listFiles, {
      owner,
      repo,
      pull_number: pullNumber,
      per_page: 100,
    }),
    github.paginate(github.rest.issues.listComments, {
      owner,
      repo,
      issue_number: pullNumber,
      per_page: 100,
    }),
    github.paginate(github.rest.pulls.list, {
      owner,
      repo,
      state: "open",
      head: `${owner}:${recoveryBranch(pullNumber)}`,
      per_page: 100,
    }),
  ]);

  // blobを持たない変更ではハッシュが無いので、空文字列として扱います。
  const key = updateKey(files.map((file) => ({ filename: file.filename, sha: file.sha ?? "" })));
  const records = parseRecoveryRecords(
    comments.map((comment) => ({
      authorLogin: comment.user?.login ?? "",
      body: comment.body ?? "",
      createdAt: comment.created_at,
    })),
  );
  core.info(`key: ${key}`);
  core.info(`過去の記録: ${JSON.stringify(records)}`);

  const decision = decide({
    repository: `${owner}/${repo}`,
    pullRequest: {
      state: pull.data.state,
      authorLogin: pull.data.user.login,
      headRef: pull.data.head.ref,
      // フォーク元が削除されたPRでは`repo`が無いので、空文字列として扱います。
      headRepository: pull.data.head.repo?.full_name ?? "",
    },
    key,
    force: process.env["FORCE"] === "true",
    records,
    openRecoveryPullRequests: recoveryPulls.length,
    now: Date.now(),
    cooldownHours,
  });
  core.info(decision.run ? "run" : `skip: ${decision.reason}`);

  core.setOutput("run", String(decision.run));
  core.setOutput("key", key);
  core.setOutput("head-ref", pull.data.head.ref);
  core.setOutput("head-sha", pull.data.head.sha);
  core.setOutput("base-sha", pull.data.base.sha);
}
