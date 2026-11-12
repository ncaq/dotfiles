/**
 * 失敗したジョブのログを保存する時の、ジョブの選び方と保存先の名前の決め方。
 *
 * GitHubとの通信を含まない部分だけをここに置いて、テストできるようにしています。
 */

/** ワークフローの実行のジョブのうち、ここで使う情報。 */
export interface JobSummary {
  readonly id: number;
  readonly name: string;
  readonly conclusion: string | null;
}

/**
 * ログを保存する対象のジョブの結論。
 * Nixのビルドが時間切れで落ちるのもRenovateの更新で起こりうるので、`timed_out`も含めます。
 */
const LOGGED_CONCLUSIONS: ReadonlySet<string> = new Set(["failure", "timed_out"]);

/** ログを保存する対象のジョブを選びます。 */
export function selectFailedJobs(jobs: readonly JobSummary[]): JobSummary[] {
  return jobs.filter((job) => job.conclusion != null && LOGGED_CONCLUSIONS.has(job.conclusion));
}

/**
 * 環境変数で渡された実行のIDを読みます。
 * 空なら`undefined`を、正の整数として読めなければ`null`を返します。
 */
export function parseRunId(value: string | undefined): number | null | undefined {
  if (value == null || value === "") {
    return undefined;
  }
  if (!/^[0-9]+$/.test(value)) {
    return null;
  }
  const runId = Number(value);
  return Number.isSafeInteger(runId) && 0 < runId ? runId : null;
}

/**
 * ジョブのログを保存するファイル名を決めます。
 *
 * ジョブ名には`renovate-recovery / recover`のように空白やスラッシュが入るので、
 * ファイル名に使える文字以外は`_`に置き換えます。
 * 同じ名前のジョブがあっても衝突しないよう、ジョブのIDを付けます。
 */
export function jobLogFileName(job: JobSummary): string {
  const safeName = job.name.replace(/[^A-Za-z0-9._-]+/g, "_").replace(/^[._]+/, "");
  return `${safeName === "" ? "job" : safeName}-${job.id}.log`;
}
