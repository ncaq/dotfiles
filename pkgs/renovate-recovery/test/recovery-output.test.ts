import { describe, expect, it } from "vitest";
import { MAX_RESULT_BYTES, rejectResultDir, rejectResultFile } from "../src/recovery-output.ts";

describe("rejectResultDir", () => {
  it("リンクではないディレクトリは使う", () => {
    expect(rejectResultDir({ isDirectory: true })).toBeUndefined();
  });

  it("リンクに置き換えられたディレクトリは使わない", () => {
    expect(rejectResultDir({ isDirectory: false })).toMatch(/リンクに置き換えられている/);
  });
});

describe("rejectResultFile", () => {
  const regular = { isFile: true, nlink: 1, size: 10 };

  it("通常のファイルは読む", () => {
    expect(rejectResultFile(regular)).toBeUndefined();
  });

  it("通常のファイルでなければ読まない", () => {
    expect(rejectResultFile({ ...regular, isFile: false })).toMatch(/通常のファイルではありません/);
  });

  it("他のファイルとハードリンクで繋がっていたら読まない", () => {
    expect(rejectResultFile({ ...regular, nlink: 2 })).toMatch(/ハードリンク/);
  });

  it("上限ちょうどの大きさなら読む", () => {
    expect(rejectResultFile({ ...regular, size: MAX_RESULT_BYTES })).toBeUndefined();
  });

  it("上限を超える大きさなら読まない", () => {
    expect(rejectResultFile({ ...regular, size: MAX_RESULT_BYTES + 1 })).toMatch(/バイトを超えて/);
  });
});
