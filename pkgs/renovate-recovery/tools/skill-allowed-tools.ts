/**
 * スキルの`allowed-tools`が範囲の無い`Bash`を許可していないかを判定する規則。
 *
 * スキルの`allowed-tools`は、そのスキルの間は`permissions.allow`の一覧に関係なく許可を広げます。
 * 範囲の無い`Bash`を許可するスキルが入ると、任意のコマンドを実行できてしまいます。
 *
 * ファイルシステムに触れない判定だけをここに置いて、テストできるようにしています。
 *
 * `src/`ではなく`tools/`に置いているのは、
 * `src/`はgithub-scriptが`node_modules`無しで読み込むので組み込み以外をimportできないためです。
 * ここはビルドの中でnode_modulesと一緒に動かすので`yaml`を使えます。
 */

import { parse } from "yaml";

/** 範囲の無い`Bash`と同じ意味になる書き方。 */
const UNRESTRICTED_BASH: ReadonlySet<string> = new Set(["Bash", "Bash(*)", "Bash(*:*)"]);

/** バイト順マーク。ソースに直接書くとリンターが不正な空白として扱うので、コードポイントから作ります。 */
export const BOM = String.fromCodePoint(0xfeff);

/** frontmatterの区切りの行か。行末の空白は許します。 */
function isFence(line: string): boolean {
  return line.trimEnd() === "---";
}

/**
 * SKILL.mdの先頭の`---`から次の`---`までのYAMLのfrontmatterを取り出します。無ければ`undefined`です。
 * 先頭のBOMは落とします。
 */
export function extractFrontmatter(markdown: string): string | undefined {
  const lines = (markdown.startsWith(BOM) ? markdown.slice(BOM.length) : markdown).split(/\r?\n/);
  if (lines[0] == null || !isFence(lines[0])) {
    return undefined;
  }
  const end = lines.findIndex((line, index) => 0 < index && isFence(line));
  if (end === -1) {
    return undefined;
  }
  return lines.slice(1, end).join("\n");
}

/**
 * `allowed-tools`の文字列の一覧を分けます。
 * 一覧はカンマ区切りでも空白区切りでも書けますが、
 * `Bash(git log:*)`のように括弧の中にも空白があるので、括弧の外の区切りだけで分けます。
 */
export function splitToolList(value: string): string[] {
  const tools: string[] = [];
  let depth = 0;
  let token = "";
  for (const char of value) {
    if (char === "(") {
      depth += 1;
    } else if (char === ")" && 0 < depth) {
      depth -= 1;
    }
    if (depth === 0 && (char === "," || /\s/.test(char))) {
      if (token !== "") {
        tools.push(token);
      }
      token = "";
    } else {
      token += char;
    }
  }
  if (token !== "") {
    tools.push(token);
  }
  return tools;
}

/** `allowed-tools`の値を個々のツールの指定の一覧にします。 */
function toolsOf(allowedTools: unknown): string[] {
  if (typeof allowedTools === "string") {
    return splitToolList(allowedTools);
  }
  if (Array.isArray(allowedTools)) {
    return allowedTools.flatMap((tool) => (typeof tool === "string" ? splitToolList(tool) : []));
  }
  return [];
}

/**
 * SKILL.mdの中身から、範囲の無い`Bash`にあたる指定を返します。無ければ空の配列です。
 *
 * この検査は権限の迂回に気付くための安全装置なので、
 * 判定できない時は見逃さずに例外を投げます。
 * スキルには`name`と`description`のfrontmatterが必ずあるので、
 * frontmatterを取り出せないか、YAMLのオブジェクトとして読めない時は判定できないものとして扱います。
 */
export function findUnrestrictedBash(markdown: string): string[] {
  const frontmatter = extractFrontmatter(markdown);
  if (frontmatter == null) {
    throw new Error("frontmatterを取り出せません");
  }
  const parsed: unknown = parse(frontmatter);
  if (parsed == null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("frontmatterがYAMLのオブジェクトではありません");
  }
  if (!("allowed-tools" in parsed)) {
    return [];
  }
  return toolsOf(parsed["allowed-tools"]).filter((tool) => UNRESTRICTED_BASH.has(tool));
}
