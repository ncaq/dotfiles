import { describe, expect, it } from "vitest";
import { jobLogFileName, selectFailedJobs } from "../src/job-log.ts";

describe("selectFailedJobs", () => {
  it("失敗したジョブだけを選ぶ", () => {
    const jobs = [
      { id: 1, name: "nix-fast-build", conclusion: "failure" },
      { id: 2, name: "build-nixos", conclusion: "success" },
      { id: 3, name: "test-nixos-boot", conclusion: "skipped" },
      { id: 4, name: "renovate-recovery / recover", conclusion: null },
    ];
    expect(selectFailedJobs(jobs).map((job) => job.id)).toEqual([1]);
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
