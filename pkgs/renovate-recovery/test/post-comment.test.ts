import { link, mkdir, mkdtemp, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import type { WarningReporter } from "../src/post-comment.ts";
import { readResult } from "../src/post-comment.ts";

/** 呼ばれた警告を記録する偽物の出力先。 */
function recordingReporter(): WarningReporter & { warnings: string[] } {
  const warnings: string[] = [];
  return { warnings, warning: (message) => warnings.push(message) };
}

/** 一時ディレクトリの中に結果のディレクトリと、その外の秘密のファイルを用意します。 */
async function prepare(): Promise<{ resultDir: string; secret: string }> {
  const root = await mkdtemp(path.join(tmpdir(), "recovery-output-"));
  const resultDir = path.join(root, "recovery");
  await mkdir(resultDir);
  const secret = path.join(root, "secret");
  await writeFile(secret, "SECRET_TOKEN", "utf8");
  return { resultDir, secret };
}

describe("readResult", () => {
  it("通常のファイルなら中身を返す", async () => {
    const { resultDir } = await prepare();
    const file = path.join(resultDir, "result.md");
    await writeFile(file, "結果です", "utf8");
    const reporter = recordingReporter();
    expect(await readResult(file, reporter)).toBe("結果です");
    expect(reporter.warnings).toEqual([]);
  });

  it("外のファイルへのシンボリックリンクは中身を読まずに拒否の文を返す", async () => {
    const { resultDir, secret } = await prepare();
    const file = path.join(resultDir, "result.md");
    await symlink(secret, file);
    const reporter = recordingReporter();
    const result = await readResult(file, reporter);
    expect(result).toMatch(/シンボリックリンク/);
    expect(result).not.toMatch(/SECRET_TOKEN/);
    expect(reporter.warnings).toHaveLength(1);
  });

  it("結果のディレクトリがシンボリックリンクなら拒否する", async () => {
    const { resultDir, secret } = await prepare();
    const outside = path.dirname(secret);
    const linkedDir = `${resultDir}-linked`;
    await symlink(outside, linkedDir);
    const reporter = recordingReporter();
    const result = await readResult(path.join(linkedDir, "secret"), reporter);
    expect(result).toMatch(/リンクに置き換えられている/);
    expect(result).not.toMatch(/SECRET_TOKEN/);
  });

  it("外のファイルへのハードリンクは拒否する", async () => {
    const { resultDir, secret } = await prepare();
    const file = path.join(resultDir, "result.md");
    await link(secret, file);
    const reporter = recordingReporter();
    const result = await readResult(file, reporter);
    expect(result).toMatch(/ハードリンク/);
    expect(result).not.toMatch(/SECRET_TOKEN/);
  });

  it("ファイルが無ければ結果なしとして扱う", async () => {
    const { resultDir } = await prepare();
    const reporter = recordingReporter();
    expect(await readResult(path.join(resultDir, "result.md"), reporter)).toBeUndefined();
    expect(reporter.warnings).toEqual([]);
  });

  it("ディレクトリが無ければ結果なしとして扱う", async () => {
    const { resultDir } = await prepare();
    const reporter = recordingReporter();
    expect(
      await readResult(path.join(resultDir, "missing", "result.md"), reporter),
    ).toBeUndefined();
    expect(reporter.warnings).toEqual([]);
  });
});
