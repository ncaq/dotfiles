// @ts-check
import { execFileSync } from "node:child_process";
import { writeFile, appendFile } from "node:fs/promises";

// ビルド前のnix storeパスのスナップショットを保存
const snapshotPath = "/tmp/niks3-pre-build-paths.txt";
const paths = execFileSync("nix", ["path-info", "--all"], {
  encoding: "utf-8",
});
await writeFile(snapshotPath, paths);
const githubState = process.env.GITHUB_STATE;
if (!githubState) throw new Error("GITHUB_STATE is not set");
await appendFile(githubState, `snapshot_path=${snapshotPath}\n`);
console.log("niks3-push: Saved pre-build store snapshot");
