/**
 * 引数に渡したSKILL.mdのうち、
 * `allowed-tools`が範囲の無い`Bash`を許可しているものを報告して、終了コード1で終わります。
 *
 * `renovate-recovery-claude-config`のビルドの中で、読み込むプラグインの全てのスキルにかけます。
 * konokaの更新で`permissions`の一覧を迂回できるスキルが入ったら気付けるようにするためです。
 */

import { readFile } from "node:fs/promises";
import process from "node:process";
import { findUnrestrictedBash } from "./skill-allowed-tools.ts";

async function main(files: readonly string[]): Promise<void> {
  let detected = false;
  for (const file of files) {
    for (const tool of findUnrestrictedBash(await readFile(file, "utf8"))) {
      console.error(`${file} が範囲の無いBashを許可しています: ${tool}`);
      detected = true;
    }
  }
  if (detected) {
    process.exitCode = 1;
  }
}

await main(process.argv.slice(2));
