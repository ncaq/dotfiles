/**
 * 引数に渡したClaude Codeの`settings.json`の`permissions.deny`を調べて、
 * `Edit`の規則に問題があれば報告して、終了コード1で終わります。
 *
 * `renovate-recovery-claude-config`のビルドの中で、生成した設定にかけます。
 * 作業ツリーを覆う拒否が入ったり、後のステップが読む場所の拒否が消えたりしたら、
 * 復旧が要る時ではなくビルドの時に気付けるようにするためです。
 * 何を確かめるかは`edit-deny-rules.ts`に書いてあります。
 *
 * 設定を読めない時や`permissions.deny`が文字列の配列ではない時も、
 * 見逃さないよう報告して終了コード1で終わります。
 */

import { readFile } from "node:fs/promises";
import process from "node:process";
import { checkEditDenyRules } from "./edit-deny-rules.ts";

/** 設定のJSONから`permissions.deny`を取り出します。文字列の配列でなければ例外にします。 */
function readDenyRules(settings: unknown): string[] {
  const permissions =
    typeof settings === "object" && settings !== null && "permissions" in settings
      ? settings.permissions
      : undefined;
  const deny =
    typeof permissions === "object" && permissions !== null && "deny" in permissions
      ? permissions.deny
      : undefined;
  if (!Array.isArray(deny) || !deny.every((rule) => typeof rule === "string")) {
    throw new Error("permissions.denyが文字列の配列ではありません");
  }
  return deny;
}

async function main(file: string | undefined): Promise<void> {
  if (file == null) {
    console.error("検査するsettings.jsonが渡されていません");
    process.exitCode = 1;
    return;
  }
  try {
    const settings: unknown = JSON.parse(await readFile(file, "utf8"));
    const problems = checkEditDenyRules(readDenyRules(settings));
    for (const problem of problems) {
      console.error(`${file}: ${problem}`);
    }
    if (problems.length !== 0) {
      process.exitCode = 1;
    }
  } catch (error) {
    console.error(
      `${file} を検査できませんでした: ${error instanceof Error ? error.message : String(error)}`,
    );
    process.exitCode = 1;
  }
}

await main(process.argv[2]);
