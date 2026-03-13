// @ts-check
import { spawn } from "node:child_process";
import { createWriteStream } from "node:fs";
import { mkdtemp, appendFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

/** nix store内の全パスをファイルに書き出す。 */
async function saveStorePathsToFile(/** @type {string} */ filePath) {
  return new Promise((resolve, reject) => {
    const child = spawn("nix", ["path-info", "--all"], { stdio: ["ignore", "pipe", "inherit"] });
    const out = createWriteStream(filePath);
    child.stdout.pipe(out);
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve(undefined);
      else reject(new Error(`nix path-info exited with code ${code}`));
    });
  });
}

async function main() {
  const tempDir = process.env.RUNNER_TEMP || tmpdir();

  // ビルド前のnix storeパスのスナップショットを保存
  const snapshotDir = await mkdtemp(join(tempDir, "niks3-snapshot-"));
  const snapshotPath = join(snapshotDir, "pre-build-paths.txt");
  await saveStorePathsToFile(snapshotPath);
  const githubState = process.env.GITHUB_STATE;
  if (githubState == null || githubState === "") {
    throw new Error("GITHUB_STATE is not set");
  }
  await appendFile(githubState, `snapshot_path=${snapshotPath}\n`);
  console.log("niks3-push: Saved pre-build store snapshot");
}

main().catch((err) => {
  console.warn(`::warning::niks3-push: Failed to save pre-build snapshot: ${err}`);
});
