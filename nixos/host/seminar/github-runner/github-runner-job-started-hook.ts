import { readFile } from "node:fs/promises";

interface GitHubEvent {
  readonly pull_request?: {
    readonly author_association?: string;
  };
  readonly sender?: {
    readonly login?: string;
  };
}

async function main(): Promise<void> {
  const eventName = process.env.GITHUB_EVENT_NAME ?? "";
  const actor = process.env.GITHUB_ACTOR ?? "";
  const eventPath = process.env.GITHUB_EVENT_PATH ?? "";

  console.log(`Job started hook: event=${eventName} actor=${actor}`);

  // リポジトリへの書き込み権限が必要なイベントは許可
  const trustedEvents = new Set(["push", "merge_group", "workflow_dispatch", "schedule"]);

  if (trustedEvents.has(eventName)) {
    console.log(`Event '${eventName}' is allowed.`);
    process.exit(0);
  }

  // PRイベントはオーナーのみ許可
  const prEvents = new Set(["pull_request", "pull_request_target"]);

  if (prEvents.has(eventName)) {
    const content = await readFile(eventPath, "utf-8");
    const event = JSON.parse(content) as GitHubEvent;
    const authorAssociation = event.pull_request?.author_association ?? "UNKNOWN";
    const sender = event.sender?.login ?? "UNKNOWN";
    console.log(`PR author_association=${authorAssociation} sender=${sender}`);

    if (authorAssociation === "OWNER") {
      console.log("PR author is OWNER, allowed.");
      process.exit(0);
    }

    console.error(`ERROR: Untrusted PR (author_association=${authorAssociation}, sender=${sender}). Rejecting job.`);
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
