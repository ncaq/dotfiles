import { describe, expect, it } from "vitest";
import { jobLogFileName, parseRunId, selectFailedJobs } from "../src/job-log.ts";

describe("selectFailedJobs", () => {
  it("失敗したジョブと時間切れのジョブだけを選ぶ", () => {
    const jobs = [
      { id: 1, name: "nix-fast-build", conclusion: "failure" },
      { id: 2, name: "build-nixos", conclusion: "success" },
      { id: 3, name: "test-nixos-boot", conclusion: "skipped" },
      { id: 4, name: "renovate-recovery / recover", conclusion: null },
      { id: 5, name: "build-home-manager", conclusion: "timed_out" },
      { id: 6, name: "build-nix-on-droid", conclusion: "cancelled" },
    ];
    expect(selectFailedJobs(jobs).map((job) => job.id)).toEqual([1, 5]);
  });
});

describe("parseRunId", () => {
  it("正の整数を読む", () => {
    expect(parseRunId("43152603489")).toBe(43152603489);
  });

  it("空なら指定なしとして扱う", () => {
    expect(parseRunId("")).toBeUndefined();
    expect(parseRunId(undefined)).toBeUndefined();
  });

  it("整数として読めない値は不正として扱う", () => {
    expect(parseRunId("abc")).toBeNull();
    expect(parseRunId("1.5")).toBeNull();
    expect(parseRunId("-1")).toBeNull();
    expect(parseRunId("0")).toBeNull();
    expect(parseRunId("99999999999999999999")).toBeNull();
  });
});

describe("jobLogFileName", () => {
  it("ジョブ名の空白やスラッシュを置き換えてIDを付ける", () => {
    expect(jobLogFileName({ id: 42, name: "renovate-recovery / recover", conclusion: null })).toBe(
      "renovate-recovery_recover-42.log",
    );
  });

  it("上の階層や隠しファイルを指す名前にしない", () => {
    expect(jobLogFileName({ id: 7, name: "../../etc", conclusion: null })).toBe("etc-7.log");
  });

  it("使える文字が残らない時は代わりの名前を使う", () => {
    expect(jobLogFileName({ id: 9, name: "日本語", conclusion: null })).toBe("job-9.log");
  });
});
