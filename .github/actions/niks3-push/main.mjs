// @ts-check
import { execFile } from "node:child_process";
import { mkdtemp, writeFile, appendFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

/** nix store内の全パスを取得する。 */
async function getAllStorePaths() {
  const { stdout } = await execFileAsync("nix", ["path-info", "--all"], {
    encoding: "utf-8",
    maxBuffer: 50 * 1024 * 1024,
  });
  return stdout;
}

try {
  const tempDir = process.env.RUNNER_TEMP || tmpdir();

  // ビルド前のnix storeパスのスナップショットを保存
  const snapshotDir = await mkdtemp(join(tempDir, "niks3-snapshot-"));
  const snapshotPath = join(snapshotDir, "pre-build-paths.txt");
  const paths = await getAllStorePaths();
  await writeFile(snapshotPath, paths);
  const githubState = process.env.GITHUB_STATE;
  if (githubState == null || githubState === "") {
    throw new Error("GITHUB_STATE is not set");
  }
  await appendFile(githubState, `snapshot_path=${snapshotPath}\n`);
  console.log("niks3-push: Saved pre-build store snapshot");
} catch (err) {
  console.warn(`::warning::niks3-push: Failed to save pre-build snapshot: ${err}`);
}
