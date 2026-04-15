/**
 * GitHub Actions Runnerのジョブ開始フック。
 *
 * ジョブ開始前に信頼できないPRを拒否します。
 * ワークフロー側のif条件が迂回された場合でもランナー側で防御します。
 * 念の為の多層防御なのでこれだけを信頼しているわけではありません。
 */

import { readFile } from "node:fs/promises";

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
    const content = await readFile(eventPath, "utf-8");
    const event = JSON.parse(content) as GitHubEvent;
    const sender = event.sender?.login ?? "UNKNOWN";
    const prHeadRepoFullName = event.pull_request?.head?.repo?.full_name ?? "UNKNOWN";
    const prBaseRepoFullName = event.pull_request?.base?.repo?.full_name ?? event.repository?.full_name ?? "UNKNOWN";
    const isInternalPullRequest =
      prHeadRepoFullName !== "UNKNOWN" && prBaseRepoFullName !== "UNKNOWN" && prHeadRepoFullName === prBaseRepoFullName;
    console.log(
      `PR head.repo.full_name=${prHeadRepoFullName} base.repo.full_name=${prBaseRepoFullName} ` +
        `internal=${String(isInternalPullRequest)} sender=${sender}`,
    );

    if (isInternalPullRequest) {
      console.log("Internal PR, allowed.");
      process.exit(0);
    }

    console.error(
      `ERROR: External PR is not allowed on self-hosted runner (sender=${sender}, ` +
        `head.repo.full_name=${prHeadRepoFullName}, base.repo.full_name=${prBaseRepoFullName}). Rejecting job.`,
    );
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
