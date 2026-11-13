import { writeFile } from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";
import type { SummaryReporter } from "../src/report-execution.ts";
import { reportExecutionFile } from "../src/report-execution.ts";
import { useTempDirs } from "./temp-dir.ts";

/** 出力された行を覚えておく偽物の出力先。 */
interface RecordingReporter extends SummaryReporter {
  readonly infos: string[];
  readonly warnings: string[];
}

/** 出力された行を覚えておく偽物の出力先を作ります。 */
function recordingReporter(): RecordingReporter {
  const infos: string[] = [];
  const warnings: string[] = [];
  return {
    infos,
    warnings,
    info: (message: string) => {
      infos.push(message);
    },
    warning: (message: string) => {
      warnings.push(message);
    },
  };
}

describe("reportExecutionFile", () => {
  const makeTempDir = useTempDirs("report-execution-");

  it("実行の記録の要約を出す", async () => {
    const file = path.join(await makeTempDir(), "execution.json");
    await writeFile(
      file,
      JSON.stringify([{ type: "result", subtype: "success", is_error: false, num_turns: 2 }]),
    );
    const reporter = recordingReporter();
    await reportExecutionFile(reporter, file);
    expect(reporter.infos).toStrictEqual([
      "result: subtype=success is_error=false num_turns=2 permission_denials=0",
    ]);
    expect(reporter.warnings).toStrictEqual([]);
  });

  it.each([undefined, ""])("ファイルが渡されていなければ警告だけを出す(%j)", async (file) => {
    const reporter = recordingReporter();
    await reportExecutionFile(reporter, file);
    expect(reporter.infos).toStrictEqual([]);
    expect(reporter.warnings).toStrictEqual([
      "実行の記録のファイルが渡されていないので、要約を省略します",
    ]);
  });

  it("ファイルが無くても例外にせず警告に留める", async () => {
    const reporter = recordingReporter();
    await reportExecutionFile(reporter, path.join(await makeTempDir(), "missing.json"));
    expect(reporter.infos).toStrictEqual([]);
    expect(reporter.warnings).toHaveLength(1);
    expect(reporter.warnings[0]).toMatch(/実行の記録を読めませんでした/);
  });

  it("JSONとして読めなくても例外にせず警告に留める", async () => {
    const file = path.join(await makeTempDir(), "execution.json");
    await writeFile(file, "{");
    const reporter = recordingReporter();
    await reportExecutionFile(reporter, file);
    expect(reporter.infos).toStrictEqual([]);
    expect(reporter.warnings[0]).toMatch(/実行の記録を読めませんでした/);
  });
});
