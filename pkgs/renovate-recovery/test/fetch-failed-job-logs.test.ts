import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";
import type { JobLogSource, LogReporter } from "../src/fetch-failed-job-logs.ts";
import { saveFailedJobLogs } from "../src/fetch-failed-job-logs.ts";
import type { JobSummary } from "../src/job-log.ts";
import { useTempDirs } from "./temp-dir.ts";

/** 呼ばれた警告と情報を記録する偽物の出力先。 */
function recordingReporter(): LogReporter & { warnings: string[]; infos: string[] } {
  const warnings: string[] = [];
  const infos: string[] = [];
  return {
    warnings,
    infos,
    info: (message) => infos.push(message),
    warning: (message) => warnings.push(message),
  };
}

/** `listJobs`が呼ばれたかを記録する偽物のGitHubの操作。 */
function recordingSource(jobs: readonly JobSummary[]): JobLogSource & { listJobsCalled: boolean } {
  const source = {
    listJobsCalled: false,
    listJobs: () => {
      source.listJobsCalled = true;
      return Promise.resolve(jobs);
    },
    downloadLog: () => Promise.resolve(""),
  };
  return source;
}

const JOBS: readonly JobSummary[] = [
  { id: 1, name: "nix-fast-build", conclusion: "failure" },
  { id: 2, name: "build-nixos", conclusion: "failure" },
  { id: 3, name: "build-home-manager", conclusion: "success" },
];

describe("saveFailedJobLogs", () => {
  const makeTempDir = useTempDirs("job-logs-");

  it("失敗したジョブのログを保存する", async () => {
    const logDir = await makeTempDir();
    const source: JobLogSource = {
      listJobs: () => Promise.resolve(JOBS),
      downloadLog: (jobId) => Promise.resolve(`log of ${jobId}`),
    };
    const reporter = recordingReporter();
    await saveFailedJobLogs(source, reporter, { runId: "100", logDir });
    expect((await readdir(logDir)).sort()).toEqual(["build-nixos-2.log", "nix-fast-build-1.log"]);
    expect(await readFile(path.join(logDir, "nix-fast-build-1.log"), "utf8")).toBe("log of 1");
    expect(reporter.warnings).toEqual([]);
  });

  it("ジョブの一覧の取得に失敗したら警告して例外を投げない", async () => {
    const logDir = await makeTempDir();
    const source: JobLogSource = {
      listJobs: () => Promise.reject(new Error("502 Bad Gateway")),
      downloadLog: () => Promise.resolve(""),
    };
    const reporter = recordingReporter();
    await saveFailedJobLogs(source, reporter, { runId: "100", logDir });
    expect(reporter.warnings).toHaveLength(1);
    expect(reporter.warnings[0]).toMatch(/502 Bad Gateway/);
  });

  it("1つのジョブのログの取得に失敗しても残りを保存する", async () => {
    const logDir = await makeTempDir();
    const source: JobLogSource = {
      listJobs: () => Promise.resolve(JOBS),
      downloadLog: (jobId) =>
        jobId === 1 ? Promise.reject(new Error("410 Gone")) : Promise.resolve(`log of ${jobId}`),
    };
    const reporter = recordingReporter();
    await saveFailedJobLogs(source, reporter, { runId: "100", logDir });
    expect(await readdir(logDir)).toEqual(["build-nixos-2.log"]);
    expect(reporter.warnings).toHaveLength(1);
    expect(reporter.warnings[0]).toMatch(/nix-fast-build.*410 Gone/);
  });

  it("保存先のディレクトリが作れなくても警告して例外を投げない", async () => {
    const parent = await makeTempDir();
    // 同じ名前のファイルがあるとディレクトリを作れない。
    const logDir = path.join(parent, "logs");
    await writeFile(logDir, "", "utf8");
    const reporter = recordingReporter();
    await saveFailedJobLogs(recordingSource(JOBS), reporter, { runId: "100", logDir });
    expect(reporter.warnings).toHaveLength(1);
    expect(reporter.warnings[0]).toMatch(/準備に失敗しました/);
  });

  it.each([
    ["未定義", undefined],
    ["空", ""],
  ])("保存先のディレクトリが%sなら取得せずに警告する", async (_name, logDir) => {
    const source = recordingSource(JOBS);
    const reporter = recordingReporter();
    await saveFailedJobLogs(source, reporter, { runId: "100", logDir });
    expect(source.listJobsCalled).toBe(false);
    expect(reporter.warnings).toHaveLength(1);
    expect(reporter.warnings[0]).toMatch(/ディレクトリが渡されていない/);
  });

  it.each([
    ["空", ""],
    ["未定義", undefined],
  ])("実行のIDが%sなら取得せず情報だけを出す", async (_name, runId) => {
    const logDir = await makeTempDir();
    const source = recordingSource(JOBS);
    const reporter = recordingReporter();
    await saveFailedJobLogs(source, reporter, { runId, logDir });
    expect(source.listJobsCalled).toBe(false);
    expect(reporter.warnings).toEqual([]);
    expect(reporter.infos).toHaveLength(1);
  });

  it("失敗したジョブが無ければ警告してファイルを作らない", async () => {
    const logDir = await makeTempDir();
    const source = recordingSource(JOBS.map((job) => ({ ...job, conclusion: "success" })));
    const reporter = recordingReporter();
    await saveFailedJobLogs(source, reporter, { runId: "100", logDir });
    expect(await readdir(logDir)).toEqual([]);
    expect(reporter.warnings).toHaveLength(1);
    expect(reporter.warnings[0]).toMatch(/失敗したジョブが見つかりません/);
  });

  it("実行のIDが不正なら取得しない", async () => {
    const source = recordingSource(JOBS);
    const reporter = recordingReporter();
    await saveFailedJobLogs(source, reporter, { runId: "abc", logDir: "/nonexistent" });
    expect(source.listJobsCalled).toBe(false);
    expect(reporter.warnings).toHaveLength(1);
    expect(reporter.warnings[0]).toMatch(/正の整数ではない/);
  });
});
