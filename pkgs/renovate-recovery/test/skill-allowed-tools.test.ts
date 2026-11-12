import { describe, expect, it } from "vitest";
import {
  extractFrontmatter,
  findUnrestrictedBash,
  splitToolList,
} from "../tools/skill-allowed-tools.ts";

/** frontmatterと本文からSKILL.mdの中身を作ります。 */
function skill(frontmatter: string, body = "本文\n"): string {
  return `---\nname: test\ndescription: Test.\n${frontmatter}---\n${body}`;
}

describe("splitToolList", () => {
  it("括弧の外のカンマと空白で分ける", () => {
    expect(splitToolList("Read, Bash(git log:*) Grep,Bash(nix build --no-link:*)")).toEqual([
      "Read",
      "Bash(git log:*)",
      "Grep",
      "Bash(nix build --no-link:*)",
    ]);
  });
});

describe("extractFrontmatter", () => {
  it("先頭の区切りが無ければ取り出さない", () => {
    expect(extractFrontmatter("本文だけ\nallowed-tools: Bash\n")).toBeUndefined();
  });
});

describe("findUnrestrictedBash", () => {
  it.each([
    ["カンマ区切り", "allowed-tools: Read, Bash\n"],
    ["空白区切り", "allowed-tools: Read Bash Grep\n"],
    ["折り返し", "allowed-tools: >-\n  Glob,\n  Bash,\n  Read\n"],
    ["リスト", "allowed-tools:\n  - Read\n  - Bash\n"],
    ["引用符", 'allowed-tools:\n  - "Bash"\n'],
    ["Bash(*)", "allowed-tools: Read, Bash(*)\n"],
    ["Bash(*:*)", "allowed-tools: Read, Bash(*:*)\n"],
  ])("%sで書かれた範囲の無いBashを検出する", (_name, frontmatter) => {
    expect(findUnrestrictedBash(skill(frontmatter))).toHaveLength(1);
  });

  it("範囲を絞ったBashは検出しない", () => {
    expect(
      findUnrestrictedBash(skill("allowed-tools: Bash(git log:*), Read Bash(nix fmt:*)\n")),
    ).toEqual([]);
  });

  it("本文にBashと書かれているだけなら検出しない", () => {
    expect(
      findUnrestrictedBash(
        skill("allowed-tools: Read\n", "Bashを使います。\nallowed-tools: Bash\n"),
      ),
    ).toEqual([]);
  });

  it("allowed-toolsが無ければ検出しない", () => {
    expect(findUnrestrictedBash(skill(""))).toEqual([]);
  });
});
