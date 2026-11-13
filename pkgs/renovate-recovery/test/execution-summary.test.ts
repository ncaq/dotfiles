import { describe, expect, it } from "vitest";
import { MAX_DETAIL_LENGTH, sanitizeDetail, summarizeExecution } from "../src/execution-summary.ts";

/** ツールの結果やClaude Codeの文章に紛れ込みうる、ログに出てはいけない文字列。 */
const SECRET = "ghp_secret_value_that_must_not_leak";

const execution = [
  {
    type: "system",
    subtype: "init",
    claude_code_version: "2.1.318",
    model: "claude-opus-5-5",
    cwd: `/run/${SECRET}`,
    plugins: [
      { name: "commit", version: "3.1.1", path: "/nix/store/x-commit" },
      { name: "research" },
    ],
    plugin_errors: [{ plugin: "pr", message: "manifest not found" }],
    mcp_servers: [
      { name: "plugin:research:mdn", status: "connected" },
      { name: "plugin:nix-tasuke:nixos", status: "failed" },
    ],
  },
  { type: "system", subtype: "hook_response", stdout: SECRET },
  {
    type: "assistant",
    message: {
      content: [
        { type: "text", text: `考えています ${SECRET}` },
        { type: "tool_use", id: "t1", name: "Bash", input: { command: `echo ${SECRET}` } },
        { type: "tool_use", id: "t2", name: "Skill", input: { skill: "commit:commit-style" } },
      ],
    },
  },
  {
    type: "user",
    message: {
      content: [
        { type: "tool_result", tool_use_id: "t1", content: `出力 ${SECRET}` },
        { type: "tool_result", tool_use_id: "t2", is_error: true, content: `失敗 ${SECRET}` },
      ],
    },
  },
  {
    type: "assistant",
    message: {
      content: [{ type: "tool_use", id: "t3", name: "Write", input: { file_path: "a.md" } }],
    },
  },
  {
    type: "result",
    subtype: "success",
    is_error: false,
    num_turns: 16,
    result: `終わりました ${SECRET}`,
    permission_denials: [
      {
        tool_name: "Write",
        tool_input: { file_path: `.renovate-recovery/${SECRET}.md`, content: SECRET },
      },
      { tool_name: "Bash", tool_input: { command: `echo ${SECRET}` } },
      { tool_name: "WebFetch", tool_input: { url: `https://example.com/?q=${SECRET}` } },
      { tool_name: "mcp__x__y", tool_input: { query: SECRET, action: "info" } },
    ],
  },
];

describe("summarizeExecution", () => {
  const lines = summarizeExecution(execution);

  it("プラグインとMCPサーバーの状態を出す", () => {
    expect(lines).toContain("init: claude_code_version=2.1.318 model=claude-opus-5-5");
    expect(lines).toContain("plugin: commit@3.1.1");
    expect(lines).toContain("plugin: research@?");
    expect(lines).toContain('plugin_error: {"plugin":"pr","message":"manifest not found"}');
    expect(lines).toContain("mcp_server: plugin:research:mdn status=connected");
    expect(lines).toContain("mcp_server: plugin:nix-tasuke:nixos status=failed");
  });

  it("呼ばれたツールの名前とエラーかどうかを、呼ばれた順に出す", () => {
    expect(lines.filter((line) => line.startsWith("tool: "))).toStrictEqual([
      "tool: Bash ok",
      "tool: Skill(commit:commit-style) error",
      "tool: Write ok",
    ]);
  });

  it("終了の種別と、拒否された呼び出しの数を出す", () => {
    expect(lines).toContain(
      "result: subtype=success is_error=false num_turns=16 permission_denials=4",
    );
  });

  it("権限で拒否された呼び出しは、ツールの名前と引数の名前だけを出す", () => {
    expect(lines.filter((line) => line.startsWith("denied: "))).toStrictEqual([
      "denied: Write keys=file_path,content",
      "denied: Bash keys=command",
      "denied: WebFetch keys=url",
      "denied: mcp__x__y keys=query,action",
    ]);
  });

  it("ツールの結果の本文も、Claude Codeの文章も、ツールの引数の値も出さない", () => {
    expect(lines.join("\n")).not.toContain(SECRET);
  });

  it("配列ではない記録は、読めなかったことだけを返す", () => {
    expect(summarizeExecution({ type: "result" })).toStrictEqual([
      "実行の記録がメッセージの配列ではありません",
    ]);
  });

  it("知らない形の要素は読み飛ばす", () => {
    expect(
      summarizeExecution([null, "text", 1, { type: "unknown" }, { type: "assistant" }]),
    ).toStrictEqual([]);
  });

  it.each([
    {
      name: "ターン数が数値でなければ?にする",
      message: { type: "result", subtype: "success", is_error: false, num_turns: "16" },
      expected: ["result: subtype=success is_error=false num_turns=? permission_denials=0"],
    },
    {
      name: "エラーかどうかが無ければエラーではないとして扱う",
      message: { type: "result", subtype: "success", num_turns: 1 },
      expected: ["result: subtype=success is_error=false num_turns=1 permission_denials=0"],
    },
    {
      name: "エラーかどうかが真偽値でなければエラーではないとして扱う",
      message: { type: "result", subtype: "success", is_error: "true", num_turns: 1 },
      expected: ["result: subtype=success is_error=false num_turns=1 permission_denials=0"],
    },
    {
      name: "終了の種別が無ければ?にする",
      message: { type: "result", is_error: true, num_turns: 1 },
      expected: ["result: subtype=? is_error=true num_turns=1 permission_denials=0"],
    },
    {
      name: "拒否された呼び出しの引数がオブジェクトでなければ説明を空にする",
      message: {
        type: "result",
        subtype: "success",
        num_turns: 1,
        permission_denials: [{ tool_name: "Bash", tool_input: "ls" }, { tool_name: "Read" }],
      },
      expected: [
        "result: subtype=success is_error=false num_turns=1 permission_denials=2",
        "denied: Bash ",
        "denied: Read ",
      ],
    },
    {
      name: "拒否された呼び出しに引数が1つも無ければ、引数の名前の一覧を空にする",
      message: {
        type: "result",
        subtype: "success",
        num_turns: 1,
        permission_denials: [{ tool_name: "TodoWrite", tool_input: {} }],
      },
      expected: [
        "result: subtype=success is_error=false num_turns=1 permission_denials=1",
        "denied: TodoWrite keys=",
      ],
    },
    {
      name: "拒否された呼び出しのツールの名前が無ければ?にする",
      message: {
        type: "result",
        subtype: "success",
        num_turns: 1,
        permission_denials: [{ tool_input: { command: "ls" } }],
      },
      expected: [
        "result: subtype=success is_error=false num_turns=1 permission_denials=1",
        "denied: ? keys=command",
      ],
    },
    {
      name: "名前の無いツールの呼び出しは?にする",
      message: { type: "assistant", message: { content: [{ type: "tool_use", id: "t1" }] } },
      expected: ["tool: ? ok"],
    },
    {
      name: "スキルの名前が文字列でなければツールの名前だけを出す",
      message: {
        type: "assistant",
        message: { content: [{ type: "tool_use", id: "t1", name: "Skill", input: { skill: 1 } }] },
      },
      expected: ["tool: Skill ok"],
    },
    {
      name: "初期化の情報が何も無ければ?にして、一覧は出さない",
      message: { type: "system", subtype: "init", plugins: "commit", mcp_servers: null },
      expected: ["init: claude_code_version=? model=?"],
    },
  ])("$name", ({ message, expected }) => {
    expect(summarizeExecution([message])).toStrictEqual(expected);
  });

  it("ログに出すどの項目に改行や行の区切りの文字を入れても、新しい行を始めさせない", () => {
    const lineSeparator = String.fromCodePoint(0x2028);
    const paragraphSeparator = String.fromCodePoint(0x2029);
    const evil = `x\n::error::injected\r${lineSeparator}y${paragraphSeparator}z`;
    const injected = summarizeExecution([
      {
        type: "system",
        subtype: "init",
        claude_code_version: evil,
        model: evil,
        plugins: [{ name: evil, version: evil }],
        plugin_errors: [evil, { message: evil }],
        mcp_servers: [{ name: evil, status: evil }],
      },
      {
        type: "assistant",
        message: {
          content: [
            { type: "tool_use", id: "t1", name: evil, input: {} },
            { type: "tool_use", id: "t2", name: "Skill", input: { skill: evil } },
          ],
        },
      },
      {
        type: "result",
        subtype: evil,
        permission_denials: [
          { tool_name: evil, tool_input: { command: "ls" } },
          { tool_name: "Other", tool_input: { [evil]: 1 } },
        ],
      },
    ]);
    // 入れた値がどの行にも届いていることを先に確かめて、項目の取りこぼしで通るのを防ぎます。
    expect(injected).toHaveLength(10);
    for (const line of injected) {
      expect(line).toContain("::error::injected");
      expect(line).not.toMatch(/[\p{Cc}\p{Zl}\p{Zp}]/u);
    }
  });
});

describe("sanitizeDetail", () => {
  it("改行を空白にして、行頭から始まるワークフローコマンドを作らせない", () => {
    expect(sanitizeDetail("ls\n::add-mask::x\r\n##[error]y")).toBe("ls ::add-mask::x  ##[error]y");
  });

  it("行や段落の区切りの文字も空白にする", () => {
    const text = `a${String.fromCodePoint(0x2028)}b${String.fromCodePoint(0x2029)}c`;
    expect(sanitizeDetail(text)).toBe("a b c");
  });

  it("上限ちょうどの長さはそのまま出す", () => {
    const text = "a".repeat(MAX_DETAIL_LENGTH);
    expect(sanitizeDetail(text)).toBe(text);
  });

  it("上限を超える長さは切り詰める", () => {
    expect(sanitizeDetail("a".repeat(MAX_DETAIL_LENGTH + 1))).toBe(
      `${"a".repeat(MAX_DETAIL_LENGTH)}...`,
    );
  });
});
