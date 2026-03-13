// @ts-check
import { mkdtemp, appendFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { listStorePaths } from "./store.mjs";

/** /nix/store内のパスを列挙してファイルに書き出す。 */
async function saveStorePathsToFile(/** @type {string} */ filePath) {
  const paths = await listStorePaths();
  await writeFile(filePath, paths.join("\n") + "\n");
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
