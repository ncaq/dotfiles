// @ts-check
import { execFile } from "node:child_process";
import { writeFile, appendFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

try {
  const tempDir = process.env.RUNNER_TEMP || tmpdir();

  // ビルド前のnix storeパスのスナップショットを保存
  const snapshotPath = join(tempDir, "niks3-pre-build-paths.txt");
  const { stdout: paths } = await execFileAsync("nix", ["path-info", "--all"], {
    encoding: "utf-8",
    maxBuffer: 50 * 1024 * 1024,
  });
  await writeFile(snapshotPath, paths);
  const githubState = process.env.GITHUB_STATE;
  if (!githubState) throw new Error("GITHUB_STATE is not set");
  await appendFile(githubState, `snapshot_path=${snapshotPath}\n`);
  console.log("niks3-push: Saved pre-build store snapshot");
} catch (err) {
  console.error("niks3-push: Failed to save pre-build snapshot:", err);
}
