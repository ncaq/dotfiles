import { describe, expect, it } from "vitest";
import { MAX_RESULT_BYTES, rejectResultFile } from "../src/recovery-output.ts";

const DIR = "/work/repo/.renovate-recovery";

describe("rejectResultFile", () => {
  it("ディレクトリの中の通常のファイルは読む", () => {
    expect(
      rejectResultFile({ isRegularFile: true, realPath: `${DIR}/result.md`, size: 10 }, DIR),
    ).toBeUndefined();
  });

  it("シンボリックリンクは読まない", () => {
    expect(
      rejectResultFile({ isRegularFile: false, realPath: "/proc/self/environ", size: 0 }, DIR),
    ).toBeDefined();
  });

  it("ディレクトリ自体がリンクで外を指していたら読まない", () => {
    expect(
      rejectResultFile({ isRegularFile: true, realPath: "/etc/passwd", size: 10 }, DIR),
    ).toBeDefined();
  });

  it("名前の前置きが同じだけの隣のディレクトリは外として扱う", () => {
    expect(
      rejectResultFile({ isRegularFile: true, realPath: `${DIR}-other/result.md`, size: 10 }, DIR),
    ).toBeDefined();
  });

  it("ディレクトリそのものは読まない", () => {
    expect(rejectResultFile({ isRegularFile: true, realPath: DIR, size: 10 }, DIR)).toBeDefined();
  });

  it("上限を超える大きさなら読まない", () => {
    expect(
      rejectResultFile(
        { isRegularFile: true, realPath: `${DIR}/result.md`, size: MAX_RESULT_BYTES + 1 },
        DIR,
      ),
    ).toBeDefined();
  });
});
