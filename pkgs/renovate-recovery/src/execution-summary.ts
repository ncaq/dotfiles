/**
 * Claude Codeの実行の記録から、公開のログに出してよい要約を作る規則。
 *
 * `claude-code-action`は会話の全文をJSONで残しますが、
 * ツールの結果にはビルドのログや読んだファイルの中身が入るので、
 * 公開のリポジトリのログにはそのまま出せません。
 * 復旧がうまく動かなかった時に原因を追えるよう、
 * 中身を含まない構造だけを取り出します。
 *
 * - 読み込まれたプラグインとMCPサーバーの状態
 * - 呼ばれたツールの名前と、エラーになったかどうか
 * - 権限で拒否された呼び出し
 * - 終了の種別とターン数
 *
 * ツールの結果の本文とClaude Codeの文章は出しません。
 * 拒否された呼び出しの引数はClaude Codeが書いた文字列なので、
 * 長さを切り詰めて制御文字を落とした上で出します。
 * 全文は暗号化したアーティファクトの方で読みます。
 *
 * 記録の形はClaude Codeの版で変わりうるので、
 * 知らない形の要素は例外にせず読み飛ばします。
 */

/** 引数などの文字列を出す時の長さの上限。 */
export const MAX_DETAIL_LENGTH = 200;

/** 拒否された呼び出しの引数のうち、何をしようとしたかが分かるもの。先に見つかったものを出します。 */
const DETAIL_KEYS = ["command", "file_path", "path", "skill", "pattern", "url"];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asArray(value: unknown): readonly unknown[] {
  return Array.isArray(value) ? value : [];
}

function asString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

/**
 * ログの1行に埋めてよい形にします。
 * 改行を含む制御文字と行や段落の区切りの文字を空白に置き換えて、
 * 行頭から始まるワークフローコマンドを作れないようにします。
 */
export function sanitizeDetail(text: string): string {
  const flattened = text.replaceAll(/[\p{Cc}\p{Zl}\p{Zp}]/gu, " ");
  return MAX_DETAIL_LENGTH < flattened.length
    ? `${flattened.slice(0, MAX_DETAIL_LENGTH)}...`
    : flattened;
}

/** ツールの引数から、何をしようとしたかが分かる短い説明を作ります。 */
function describeToolInput(input: unknown): string {
  if (!isRecord(input)) {
    return "";
  }
  for (const key of DETAIL_KEYS) {
    const value = asString(input[key]);
    if (value != null) {
      return `${key}=${sanitizeDetail(value)}`;
    }
  }
  return `keys=${sanitizeDetail(Object.keys(input).join(","))}`;
}

/** 文字列の項目をログに出す形にします。文字列でなければ`?`にします。 */
function field(value: unknown): string {
  return sanitizeDetail(asString(value) ?? "?");
}

/** 初期化のメッセージから、プラグインとMCPサーバーの状態を取り出します。 */
function summarizeInit(message: Record<string, unknown>): string[] {
  const version = field(message["claude_code_version"]);
  const model = field(message["model"]);
  return [
    `init: claude_code_version=${version} model=${model}`,
    ...asArray(message["plugins"])
      .filter(isRecord)
      .map((plugin) => `plugin: ${field(plugin["name"])}@${field(plugin["version"])}`),
    // プラグインのエラーはClaude Code自身が作る文なので、形を決めつけずにJSONのまま出します。
    ...asArray(message["plugin_errors"]).map(
      (error) => `plugin_error: ${sanitizeDetail(JSON.stringify(error))}`,
    ),
    ...asArray(message["mcp_servers"])
      .filter(isRecord)
      .map((server) => `mcp_server: ${field(server["name"])} status=${field(server["status"])}`),
  ];
}

/** メッセージの中身の要素のうち、指定した種類のものを返します。 */
function contentBlocks(message: Record<string, unknown>, type: string): Record<string, unknown>[] {
  const inner = message["message"];
  if (!isRecord(inner)) {
    return [];
  }
  return asArray(inner["content"])
    .filter(isRecord)
    .filter((block) => block["type"] === type);
}

/** 終了のメッセージから、終了の種別と拒否された呼び出しを取り出します。 */
function summarizeResult(message: Record<string, unknown>): string[] {
  const denials = asArray(message["permission_denials"]).filter(isRecord);
  const numTurns = message["num_turns"];
  const fields = [
    `subtype=${field(message["subtype"])}`,
    `is_error=${String(message["is_error"] === true)}`,
    `num_turns=${typeof numTurns === "number" ? String(numTurns) : "?"}`,
    `permission_denials=${String(denials.length)}`,
  ];
  return [
    `result: ${fields.join(" ")}`,
    ...denials.map(
      (denial) =>
        `denied: ${field(denial["tool_name"])} ${describeToolInput(denial["tool_input"])}`,
    ),
  ];
}

/**
 * エラーになったツールの呼び出しのIDを集めます。
 * ツールの結果は呼び出しの後に別のメッセージで届くので、要約を作る前に全体から集めます。
 */
function collectFailedToolUseIds(messages: readonly Record<string, unknown>[]): Set<string> {
  return new Set(
    messages
      .filter((message) => message["type"] === "user")
      .flatMap((message) => contentBlocks(message, "tool_result"))
      .filter((block) => block["is_error"] === true)
      .map((block) => asString(block["tool_use_id"]))
      .filter((id) => id != null),
  );
}

/** Claude Codeのメッセージから、呼ばれたツールの名前とエラーになったかどうかを取り出します。 */
function summarizeToolUses(
  message: Record<string, unknown>,
  failedToolUseIds: ReadonlySet<string>,
): string[] {
  return contentBlocks(message, "tool_use").map((block) => {
    const name = asString(block["name"]) ?? "?";
    // スキルは名前が分からないとどのプラグインの話か追えないので、スキルの名前だけ添えます。
    const input = block["input"];
    const skill = name === "Skill" && isRecord(input) ? asString(input["skill"]) : undefined;
    const label = skill == null ? name : `${name}(${skill})`;
    const status = failedToolUseIds.has(asString(block["id"]) ?? "") ? "error" : "ok";
    return `tool: ${sanitizeDetail(label)} ${status}`;
  });
}

/**
 * 実行の記録を、ログに出す行の列にします。
 * 記録はメッセージの配列で、それ以外の形なら何も読めなかったことを1行で返します。
 */
export function summarizeExecution(execution: unknown): string[] {
  if (!Array.isArray(execution)) {
    return ["実行の記録がメッセージの配列ではありません"];
  }
  const messages = execution.filter(isRecord);
  const failedToolUseIds = collectFailedToolUseIds(messages);
  return messages.flatMap((message) => {
    switch (message["type"]) {
      case "system":
        return message["subtype"] === "init" ? summarizeInit(message) : [];
      case "assistant":
        return summarizeToolUses(message, failedToolUseIds);
      case "result":
        return summarizeResult(message);
      default:
        return [];
    }
  });
}
