import { describe, expect, it } from "vitest";
import { buildCommentBody, parseRecoveryRecords } from "../src/comment.ts";

const KEY = "0123456789abcdef";
const RUN_URL = "https://github.com/owner/repo/actions/runs/1";
const CREATED_AT = "2026-11-10T12:00:00Z";

describe("parseRecoveryRecords", () => {
  it("投稿したコメントから同じキーを読み戻せる", () => {
    const body = buildCommentBody({
      key: KEY,
      result: "nixpkgs-unstableを除外しました。",
      runUrl: RUN_URL,
    });
    const records = parseRecoveryRecords([
      { authorLogin: "github-actions[bot]", body, createdAt: CREATED_AT },
    ]);
    expect(records).toEqual([{ key: KEY, recordedAt: Date.parse(CREATED_AT) }]);
  });

  it("目印の無いコメントは無視する", () => {
    const records = parseRecoveryRecords([
      {
        authorLogin: "github-actions[bot]",
        body: "<!-- nvd-pr-diff -->\n## nvd diff",
        createdAt: CREATED_AT,
      },
    ]);
    expect(records).toEqual([]);
  });

  it("他のアカウントが目印を真似たコメントは無視する", () => {
    const body = buildCommentBody({ key: KEY, result: "偽の記録", runUrl: RUN_URL });
    const records = parseRecoveryRecords([{ authorLogin: "someone", body, createdAt: CREATED_AT }]);
    expect(records).toEqual([]);
  });

  it("本文の途中にある目印は記録として扱わない", () => {
    const records = parseRecoveryRecords([
      {
        authorLogin: "github-actions[bot]",
        body: `引用:\n<!-- renovate-recovery key=${KEY} -->`,
        createdAt: CREATED_AT,
      },
    ]);
    expect(records).toEqual([]);
  });
});

describe("buildCommentBody", () => {
  it("結果と実行ログへのリンクを載せる", () => {
    const body = buildCommentBody({ key: KEY, result: "原因はupstreamです。\n", runUrl: RUN_URL });
    expect(body).toBe(
      [
        `<!-- renovate-recovery key=${KEY} -->`,
        "## renovate-recovery",
        "",
        "原因はupstreamです。",
        "",
        `[実行ログ](${RUN_URL})`,
        "",
      ].join("\n"),
    );
  });

  it("結果が無い時は実行ログを見るよう案内する", () => {
    const expected = "Claude Codeが結果を残さずに終了しました。実行ログを確認してください。";
    const missing = buildCommentBody({ key: KEY, result: undefined, runUrl: RUN_URL });
    const blank = buildCommentBody({ key: KEY, result: " \n", runUrl: RUN_URL });
    expect(missing).toContain(expected);
    expect(blank).toContain(expected);
  });
});
