/**
 * GitHub Actions Runnerのジョブ開始フック。
 *
 * ジョブ開始前に信頼できないPRを拒否します。
 * ワークフロー側のif条件が迂回された場合でもランナ側で防御します。
 * 念の為の多層防御なのでこれだけを信頼しているわけではありません。
 */

import { readFile, realpath } from "node:fs/promises";
import { resolve } from "node:path";

/**
 * ランナがイベントのペイロードを書き出すディレクトリの親。
 *
 * nixpkgsの`services.github-runners`は`workDir`を指定しないと、
 * systemdの`RuntimeDirectory`である`/run/github-runner/<name>`を作業ディレクトリにします。
 * ランナはその下の`_temp/_github_workflow/event.json`にペイロードを書き出します。
 */
const runnerRoot = "/run/github-runner/";

interface GitHubEvent {
  readonly pull_request?: {
    readonly author_association?: string;
    readonly head?: {
      readonly repo?: {
        readonly full_name?: string;
      };
    };
    readonly base?: {
      readonly repo?: {
        readonly full_name?: string;
      };
    };
    readonly user?: {
      readonly login?: string;
    };
  };
  readonly repository?: {
    readonly full_name?: string;
  };
  readonly sender?: {
    readonly login?: string;
  };
}

async function main(): Promise<void> {
  const eventName = process.env["GITHUB_EVENT_NAME"] ?? "";
  const actor = process.env["GITHUB_ACTOR"] ?? "";
  const eventPath = process.env["GITHUB_EVENT_PATH"] ?? "";

  console.log(`Job started hook: event=${eventName} actor=${actor}`);

  // リポジトリへの書き込み権限が必要なイベントは許可
  const trustedEvents = new Set(["push", "merge_group", "workflow_dispatch", "schedule"]);

  if (trustedEvents.has(eventName)) {
    console.log(`Event '${eventName}' is allowed.`);
    process.exit(0);
  }

  // PRイベントは内部PRのみ許可
  const prEvents = new Set(["pull_request", "pull_request_target"]);

  if (prEvents.has(eventName)) {
    // 環境変数で渡されたパスをそのまま読むと、
    // 環境変数を差し替えられた時に偽のペイロードで判定することになります。
    // ランナが書き出す場所にあることを、
    // `..`を畳んだ時点と、シンボリックリンクを解決した時点の両方で確かめます。
    const normalizedEventPath = resolve(eventPath);
    if (!normalizedEventPath.startsWith(runnerRoot)) {
      throw new Error(`Event path '${normalizedEventPath}' is outside '${runnerRoot}'.`);
    }
    const realEventPath = await realpath(normalizedEventPath);
    if (!realEventPath.startsWith(runnerRoot)) {
      throw new Error(`Event path '${realEventPath}' is outside '${runnerRoot}'.`);
    }
    const content = await readFile(realEventPath, "utf-8");
    const event = JSON.parse(content) as GitHubEvent;
    const sender = event.sender?.login;
    const prHeadRepoFullName = event.pull_request?.head?.repo?.full_name;
    const prBaseRepoFullName =
      event.pull_request?.base?.repo?.full_name ?? event.repository?.full_name;
    const isInternalPullRequest =
      prHeadRepoFullName != null &&
      prBaseRepoFullName != null &&
      prHeadRepoFullName === prBaseRepoFullName;
    console.log(
      `PR head.repo.full_name=${prHeadRepoFullName} base.repo.full_name=${prBaseRepoFullName} ` +
        `internal=${String(isInternalPullRequest)} sender=${sender}`,
    );

    if (isInternalPullRequest) {
      console.log("Internal PR, allowed.");
      process.exit(0);
    }

    const errHeader = "Rejecting job. External PR is not allowed on self-hosted runner: ";
    const errInfo = [
      `sender=${sender}`,
      `head.repo.full_name=${prHeadRepoFullName}`,
      `base.repo.full_name=${prBaseRepoFullName}`,
    ].join(", ");
    console.error(errHeader + errInfo);
    process.exit(1);
  }

  // 未知のイベントは拒否
  console.error(`ERROR: Unknown event type '${eventName}'. Rejecting job.`);
  process.exit(1);
}

main().catch((error: unknown) => {
  console.error("ERROR: Unexpected error in job-started hook:", error);
  process.exit(1);
});
