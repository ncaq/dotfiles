/**
 * 復旧の結果としてRenovateのPRへ投稿するコメント。
 *
 * コメントは人間への報告であると同時に、処理済みの記録でもあります。
 * 先頭に埋めた目印を次回の判定が読むので、外部に状態を持つ必要がありません。
 */

/** PRについたコメントのうち、記録の読み取りに使う部分。 */
export interface IssueComment {
  readonly authorLogin: string;
  readonly body: string;
  /** ISO 8601形式の投稿時刻。 */
  readonly createdAt: string;
}

/** 目印つきのコメントを投稿するアカウント。`GITHUB_TOKEN`で投稿するとこの名前になります。 */
const COMMENT_AUTHOR = "github-actions[bot]";

const MARKER_PATTERN = /^<!-- renovate-recovery key=([0-9a-f]+) -->/;

/** 過去に行った復旧の記録。 */
export interface RecoveryRecord {
  /** その時の更新の内容のキー。 */
  readonly key: string;
  /** 記録した時刻。UNIXエポックからのミリ秒。 */
  readonly recordedAt: number;
}

export function formatMarker(key: string): string {
  return `<!-- renovate-recovery key=${key} -->`;
}

/**
 * PRのコメントから復旧の記録を読み取ります。
 * 他のアカウントが目印を真似て書いても記録としては扱いません。
 */
export function parseRecoveryRecords(comments: readonly IssueComment[]): readonly RecoveryRecord[] {
  return comments
    .filter((comment) => comment.authorLogin === COMMENT_AUTHOR)
    .flatMap((comment) => {
      const key = MARKER_PATTERN.exec(comment.body)?.[1];
      return key == null ? [] : [{ key, recordedAt: Date.parse(comment.createdAt) }];
    });
}

export interface CommentContent {
  readonly key: string;
  /** Claude Codeが書いた結果。書かずに終了した時は`undefined`。 */
  readonly result: string | undefined;
  readonly runUrl: string;
}

export function buildCommentBody(content: CommentContent): string {
  const result = content.result?.trim();
  return [
    formatMarker(content.key),
    "## renovate-recovery",
    "",
    result == null || result === ""
      ? "Claude Codeが結果を残さずに終了しました。実行ログを確認してください。"
      : result,
    "",
    `[実行ログ](${content.runUrl})`,
    "",
  ].join("\n");
}
