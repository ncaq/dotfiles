import { describe, expect, it } from "vitest";
import {
  RUNNER_LAYOUT,
  checkEditDenyRules,
  editRulePattern,
  findDenyingRules,
  resolveEditPattern,
} from "../tools/edit-deny-rules.ts";

/**
 * 問題が無いと判定されるべき規則の例。判定のテストの土台にします。
 * `claude-config.nix`の設定から読んだものではないので、設定が変わってもここは変わりません。
 * 実際の設定の検査は、ビルドの中で`tools/check-edit-deny-rules.ts`が行います。
 */
const baselineRules = [
  "Edit(./.git/**)",
  "Edit(./check.sh)",
  "Edit(./.github/workflows/**)",
  "Edit(//run/github-runner/*/_temp/**)",
  "Edit(//run/github-runner/*/_actions/**)",
  "Edit(//run/github-runner/*/_tool/**)",
  "Edit(~/.gitconfig)",
  "Edit(~/.config/**)",
  "Read(//proc/**)",
  "Bash(git commit*)",
];

describe("editRulePattern", () => {
  it("Editの規則の中身を返す", () => {
    expect(editRulePattern("Edit(~/**)")).toBe("~/**");
  });

  it.each(["Read(//proc/**)", "Bash(git commit*)", "Edit", "MultiEdit(./a)"])(
    "Editの規則でなければ返さない(%s)",
    (rule) => {
      expect(editRulePattern(rule)).toBeUndefined();
    },
  );
});

describe("resolveEditPattern", () => {
  it("//で始まるものはファイルシステムの絶対パスにする", () => {
    expect(resolveEditPattern("//run/x/**", RUNNER_LAYOUT)).toBe("/run/x/**");
  });

  it("~/で始まるものはホームディレクトリからのパスにする", () => {
    expect(resolveEditPattern("~/.config/**", RUNNER_LAYOUT)).toBe(
      "/run/github-runner/dotfiles-x64-0/.config/**",
    );
  });

  it("./で始まるものは作業ディレクトリからのパスにする", () => {
    expect(resolveEditPattern("./check.sh", RUNNER_LAYOUT)).toBe(
      "/run/github-runner/dotfiles-x64-0/dotfiles/dotfiles/check.sh",
    );
  });

  it.each(["/src/**", "src/**", "**", "*.md"])("知らない書き方は判定しない(%s)", (pattern) => {
    expect(resolveEditPattern(pattern, RUNNER_LAYOUT)).toBeUndefined();
  });
});

describe("findDenyingRules", () => {
  it("ホームディレクトリの全体の拒否は、その中の作業ツリーのドットで始まる場所にも当たる", () => {
    expect(
      findDenyingRules(
        ["Edit(~/**)", "Edit(./check.sh)"],
        RUNNER_LAYOUT,
        `${RUNNER_LAYOUT.cwd}/.renovate-recovery/result.md`,
      ),
    ).toStrictEqual(["Edit(~/**)"]);
  });

  it("*は1つの階層にだけ当たる", () => {
    const rules = ["Edit(//run/github-runner/*/_temp/**)"];
    expect(
      findDenyingRules(rules, RUNNER_LAYOUT, "/run/github-runner/other/_temp/a/b"),
    ).toStrictEqual(rules);
    expect(findDenyingRules(rules, RUNNER_LAYOUT, "/run/github-runner/a/b/_temp/c")).toStrictEqual(
      [],
    );
  });
});

describe("checkEditDenyRules", () => {
  it("土台の規則の例には問題が無い", () => {
    expect(checkEditDenyRules(baselineRules)).toStrictEqual([]);
  });

  it("ホームディレクトリの全体を拒否すると、作業ツリーへ書けないことを報告する", () => {
    const problems = checkEditDenyRules([...baselineRules, "Edit(~/**)"]);
    expect(problems).toContain(
      "Edit(~/**) が作業ツリーの .renovate-recovery/result.md への書き込みを拒否しています",
    );
    expect(problems).toContain("Edit(~/**) が作業ツリーの flake.lock への書き込みを拒否しています");
  });

  it("作業ディレクトリの全体を拒否しても報告する", () => {
    expect(checkEditDenyRules([...baselineRules, "Edit(./**)"])).not.toStrictEqual([]);
  });

  it.each([
    ["Edit(//run/github-runner/*/_temp/**)", "_temp/renovate-recovery-src/post-comment.ts"],
    ["Edit(//run/github-runner/*/_actions/**)", "_actions/actions/github-script/v9/dist/index.js"],
    ["Edit(//run/github-runner/*/_tool/**)", "_tool/node/bin/node"],
    ["Edit(~/.gitconfig)", ".gitconfig"],
    ["Edit(~/.config/**)", ".config/git/config"],
    ["Edit(./.git/**)", "dotfiles/dotfiles/.git/config"],
    ["Edit(./check.sh)", "dotfiles/dotfiles/check.sh"],
    ["Edit(./.github/workflows/**)", "dotfiles/dotfiles/.github/workflows/check.yml"],
  ])("%s が消えたら、守られなくなった場所を報告する", (removed, unprotected) => {
    expect(checkEditDenyRules(baselineRules.filter((rule) => rule !== removed))).toContain(
      `${RUNNER_LAYOUT.home}/${unprotected} への書き込みを拒否する規則がありません`,
    );
  });

  it("自分のランナーの_tempだけを拒否する規則では、他のランナーの分を報告する", () => {
    const rules = baselineRules.map((rule) =>
      rule === "Edit(//run/github-runner/*/_temp/**)"
        ? "Edit(//run/github-runner/dotfiles-x64-0/_temp/**)"
        : rule,
    );
    expect(checkEditDenyRules(rules)).toStrictEqual([
      "/run/github-runner/dotfiles-x64-1/_temp/set_env への書き込みを拒否する規則がありません",
    ]);
  });

  it("判定できない書き方のEditの規則を報告する", () => {
    expect(checkEditDenyRules([...baselineRules, "Edit(secrets/**)"])).toStrictEqual([
      "Edit(secrets/**) は判定できない書き方です",
    ]);
  });
});
