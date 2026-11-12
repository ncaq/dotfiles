/**
 * 引数に渡したSKILL.mdのうち、
 * `allowed-tools`が範囲の無い`Bash`を許可しているものを報告して、終了コード1で終わります。
 *
 * `renovate-recovery-claude-config`のビルドの中で、読み込むプラグインの全てのスキルにかけます。
 * konokaの更新で`permissions`の一覧を迂回できるスキルが入ったら気付けるようにするためです。
 *
 * ファイルを読めない時や、frontmatterを取り出せず判定できない時も、
 * 見逃さないようファイル名を報告して終了コード1で終わります。
 * 検出と処理の失敗は標準エラーの出力で見分けます。
 * 呼び出し元はどちらでもビルドを落とすので、終了コードでは区別しません。
 */

import { readFile } from "node:fs/promises";
import process from "node:process";
import { findUnrestrictedBash } from "./skill-allowed-tools.ts";

/** 例外を報告に載せる文字列にします。 */
function describeError(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function main(files: readonly string[]): Promise<void> {
  let failed = false;
  for (const file of files) {
    try {
      for (const tool of findUnrestrictedBash(await readFile(file, "utf8"))) {
        console.error(`${file} が範囲の無いBashを許可しています: ${tool}`);
        failed = true;
      }
    } catch (error) {
      console.error(`${file} を検査できませんでした: ${describeError(error)}`);
      failed = true;
    }
  }
  if (failed) {
    process.exitCode = 1;
  }
}

await main(process.argv.slice(2));
