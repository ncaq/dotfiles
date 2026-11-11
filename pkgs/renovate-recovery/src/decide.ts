/**
 * Claude Codeを起動するかどうかの判定。
 *
 * RenovateはmasterがすすむたびにPRをrebaseするので、CIは同じ原因で何度も失敗します。
 * そのたびにClaude Codeを動かさないよう、ここで弾きます。
 */

import { createHash } from "node:crypto";
import type { RecoveryRecord } from "./comment.ts";

/** PRの情報のうち、判定に使う部分。 */
export interface PullRequest {
  readonly state: string;
  readonly authorLogin: string;
  readonly headRef: string;
  /** `owner/repo`の形式の、headのブランチがあるリポジトリ。 */
  readonly headRepository: string;
}

/** PRが変更するファイル。 */
export interface PullRequestFile {
  readonly filename: string;
  /** 変更後のblobのハッシュ。 */
  readonly sha: string;
}

const RENOVATE_LOGIN = "renovate[bot]";
const RENOVATE_BRANCH_PREFIX = "renovate/";

/** 復旧のPRのブランチ名。RenovateのPRごとに1つに固定します。 */
export function recoveryBranch(pullNumber: number): string {
  return `renovate-recovery/${pullNumber}`;
}

/**
 * PRが変更するファイルのblobのハッシュから、更新の内容のキーを作ります。
 * rebaseでコミットのハッシュが変わっても、更新の内容が同じならキーは変わりません。
 */
export function updateKey(files: readonly PullRequestFile[]): string {
  const lines = files.map((file) => `${file.filename} ${file.sha}\n`).toSorted();
  return createHash("sha256").update(lines.join("")).digest("hex").slice(0, 16);
}

export interface DecideInput {
  /** `owner/repo`の形式の、ワークフローが動いているリポジトリ。 */
  readonly repository: string;
  readonly pullRequest: PullRequest;
  /** 今回の更新の内容のキー。 */
  readonly key: string;
  /** 抑止の条件を無視するかどうか。対象のPRであるかの条件は無視しません。 */
  readonly force: boolean;
  readonly records: readonly RecoveryRecord[];
  /** 復旧のPRが開いたままになっている数。 */
  readonly openRecoveryPullRequests: number;
  /** 現在時刻。UNIXエポックからのミリ秒。 */
  readonly now: number;
  /** 同じPRに対して次に動かすまで空ける時間。 */
  readonly cooldownHours: number;
}

export type Decision = { readonly run: true } | { readonly run: false; readonly reason: string };

function skip(reason: string): Decision {
  return { run: false, reason };
}

/** 対象がこのリポジトリのブランチから出ている開いたRenovateのPRかどうかを調べます。 */
function rejectNonTarget(input: DecideInput): Decision | undefined {
  const { pullRequest } = input;
  if (pullRequest.state !== "open") {
    return skip("PRが開いていません");
  }
  if (pullRequest.authorLogin !== RENOVATE_LOGIN) {
    return skip("RenovateのPRではありません");
  }
  if (pullRequest.headRepository !== input.repository) {
    return skip("フォークからのPRです");
  }
  if (!pullRequest.headRef.startsWith(RENOVATE_BRANCH_PREFIX)) {
    return skip("Renovateのブランチではありません");
  }
  return undefined;
}

/** 過去の記録から見て今回は動かさなくてよいかどうかを調べます。 */
function rejectAlreadyHandled(input: DecideInput): Decision | undefined {
  if (input.records.some((record) => record.key === input.key)) {
    return skip("同じ内容の更新は処理済みです");
  }
  // lock file maintenanceはrebaseのたびに内容が変わるので、キーだけでは防げません。
  const cooldownMilliseconds = input.cooldownHours * 60 * 60 * 1000;
  if (input.records.some((record) => input.now - record.recordedAt < cooldownMilliseconds)) {
    return skip(`前回の復旧から${input.cooldownHours}時間が経っていません`);
  }
  // 復旧のPRが開いたままなら、人間がそれを処理するまで待ちます。
  if (input.openRecoveryPullRequests > 0) {
    return skip("復旧のPRが開いたままです");
  }
  return undefined;
}

export function decide(input: DecideInput): Decision {
  return (
    rejectNonTarget(input) ??
    (input.force ? undefined : rejectAlreadyHandled(input)) ?? { run: true }
  );
}
