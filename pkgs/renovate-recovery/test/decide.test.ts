import { describe, expect, it } from "vitest";
import { decide, updateKey, type DecideInput } from "../src/decide.ts";

const HOUR = 60 * 60 * 1000;
const NOW = Date.parse("2026-11-11T00:00:00Z");

/** 何も抑止されず起動する入力。各テストはここから1箇所だけ変えます。 */
const base: DecideInput = {
  repository: "owner/repo",
  pullRequest: {
    state: "open",
    authorLogin: "renovate[bot]",
    headRef: "renovate/lock-file-maintenance",
    headRepository: "owner/repo",
  },
  key: "aaaa",
  force: false,
  records: [],
  openRecoveryPullRequests: 0,
  now: NOW,
  cooldownHours: 20,
};

describe("decide", () => {
  it("記録の無いRenovateのPRでは起動する", () => {
    expect(decide(base)).toEqual({ run: true });
  });

  it("閉じたPRでは起動しない", () => {
    const decision = decide({ ...base, pullRequest: { ...base.pullRequest, state: "closed" } });
    expect(decision).toEqual({ run: false, reason: "PRが開いていません" });
  });

  it("Renovate以外が作ったPRでは起動しない", () => {
    const decision = decide({
      ...base,
      pullRequest: { ...base.pullRequest, authorLogin: "someone" },
    });
    expect(decision).toEqual({ run: false, reason: "RenovateのPRではありません" });
  });

  it("フォークからのPRでは起動しない", () => {
    const decision = decide({
      ...base,
      pullRequest: { ...base.pullRequest, headRepository: "fork/repo" },
    });
    expect(decision).toEqual({ run: false, reason: "フォークからのPRです" });
  });

  it("Renovateのブランチではないなら起動しない", () => {
    const decision = decide({
      ...base,
      pullRequest: { ...base.pullRequest, headRef: "renovate-recovery/1" },
    });
    expect(decision).toEqual({ run: false, reason: "Renovateのブランチではありません" });
  });

  it("同じキーの記録があれば古くても起動しない", () => {
    const decision = decide({
      ...base,
      records: [{ key: "aaaa", recordedAt: NOW - 72 * HOUR }],
    });
    expect(decision).toEqual({ run: false, reason: "同じ内容の更新は処理済みです" });
  });

  it("別のキーでも前回から間が空いていなければ起動しない", () => {
    const decision = decide({
      ...base,
      records: [{ key: "bbbb", recordedAt: NOW - 19 * HOUR }],
    });
    expect(decision).toEqual({ run: false, reason: "前回の復旧から20時間が経っていません" });
  });

  it("別のキーで前回から間が空いていれば起動する", () => {
    const decision = decide({
      ...base,
      records: [{ key: "bbbb", recordedAt: NOW - 20 * HOUR }],
    });
    expect(decision).toEqual({ run: true });
  });

  it("古い記録に新しい記録が混ざっていれば起動しない", () => {
    const decision = decide({
      ...base,
      records: [
        { key: "bbbb", recordedAt: NOW - 72 * HOUR },
        { key: "cccc", recordedAt: NOW - HOUR },
      ],
    });
    expect(decision.run).toBe(false);
  });

  it("復旧のPRが開いたままなら起動しない", () => {
    const decision = decide({ ...base, openRecoveryPullRequests: 1 });
    expect(decision).toEqual({ run: false, reason: "復旧のPRが開いたままです" });
  });

  it("forceなら抑止の条件を全て無視して起動する", () => {
    const decision = decide({
      ...base,
      force: true,
      records: [{ key: "aaaa", recordedAt: NOW - HOUR }],
      openRecoveryPullRequests: 1,
    });
    expect(decision).toEqual({ run: true });
  });

  it("forceでもRenovateのPRでなければ起動しない", () => {
    const decision = decide({
      ...base,
      force: true,
      pullRequest: { ...base.pullRequest, authorLogin: "someone" },
    });
    expect(decision.run).toBe(false);
  });
});

describe("updateKey", () => {
  const files = [
    { filename: "flake.lock", sha: "1111" },
    { filename: "Cargo.lock", sha: "2222" },
  ];

  it("ファイルの並び順に依存しない", () => {
    expect(updateKey(files.toReversed())).toBe(updateKey(files));
  });

  it("blobのハッシュが変わるとキーも変わる", () => {
    const changed = [{ filename: "flake.lock", sha: "3333" }, ...files.slice(1)];
    expect(updateKey(changed)).not.toBe(updateKey(files));
  });

  it("16桁の16進数を返す", () => {
    expect(updateKey(files)).toMatch(/^[0-9a-f]{16}$/);
  });
});
