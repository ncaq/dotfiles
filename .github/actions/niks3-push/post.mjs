// @ts-check
import { execFile } from "node:child_process";
import { mkdtemp, readFile, writeFile, unlink, rmdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const tempDir = process.env.RUNNER_TEMP || tmpdir();
const SERVER_URL = "https://niks3-public.ncaq.net";

async function getOidcToken() {
  const requestUrl = process.env.ACTIONS_ID_TOKEN_REQUEST_URL;
  const requestToken = process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN;

  if (!requestUrl || !requestToken) {
    console.log("niks3-push: OIDC not available, skipping push");
    return;
  }

  const url = `${requestUrl}&audience=${encodeURIComponent(SERVER_URL)}`;
  const response = await fetch(url, {
    headers: { Authorization: `bearer ${requestToken}` },
  });
  if (!response.ok) {
    throw new Error(`OIDC token request failed: ${response.status} ${response.statusText}`);
  }
  const { value } = await response.json();
  if (typeof value !== "string" || value.length === 0) {
    throw new Error("OIDC token response did not contain a valid token");
  }
  return value;
}

/** トークンを取得してストアパスを1件pushする。一時ファイルは呼び出しごとに隔離する。 */
async function pushStorePath(/** @type {string} */ niks3Bin, /** @type {string} */ storePath) {
  const freshToken = await getOidcToken();
  if (!freshToken) {
    throw new Error("OIDC token unavailable during push");
  }
  const tokenDir = await mkdtemp(join(tempDir, "niks3-token-"));
  const tokenFile = join(tokenDir, "token");
  try {
    await writeFile(tokenFile, freshToken, { mode: 0o600 });
    await execFileAsync(`${niks3Bin}/bin/niks3`, ["push", storePath], {
      env: {
        ...process.env,
        NIKS3_SERVER_URL: SERVER_URL,
        NIKS3_AUTH_TOKEN_FILE: tokenFile,
      },
    });
  } finally {
    await unlink(tokenFile).catch(() => {});
    await rmdir(tokenDir).catch(() => {});
  }
}

try {
  const snapshotPath = process.env.STATE_snapshot_path;
  if (!snapshotPath) {
    console.log("niks3-push: No snapshot found, skipping push");
    process.exit(0);
  }

  // ビルド前後のnix storeの差分を計算
  const prePaths = new Set((await readFile(snapshotPath, "utf-8")).trim().split("\n").filter(Boolean));
  const { stdout: currentPathsOutput } = await execFileAsync("nix", ["path-info", "--all"], {
    encoding: "utf-8",
    maxBuffer: 50 * 1024 * 1024,
  });
  const currentPaths = currentPathsOutput.trim().split("\n").filter(Boolean);
  const newPaths = currentPaths.filter((p) => !prePaths.has(p));

  if (newPaths.length === 0) {
    console.log("niks3-push: No new store paths to push");
    process.exit(0);
  }

  console.log(`niks3-push: Found ${newPaths.length} new store paths to push`);

  // OIDCが利用可能か確認
  const initialToken = await getOidcToken();
  if (!initialToken) process.exit(0);

  // niks3をビルドしてバイナリパスを取得
  const niks3Ref = "git+https://github.com/Mic92/niks3?ref=v1.4.0&rev=bb87dcb1b46a1f0c9426b733f4fe325245e386fa";
  const { stdout: niks3BuildOutput } = await execFileAsync(
    "nix",
    ["build", "--no-link", "--print-out-paths", niks3Ref],
    { encoding: "utf-8" },
  );
  const niks3Bin = niks3BuildOutput.trim();

  let failureCount = 0;
  try {
    for (const [i, storePath] of newPaths.entries()) {
      try {
        console.log(`niks3-push: Pushing ${i + 1}/${newPaths.length}: ${storePath}`);
        await pushStorePath(niks3Bin, storePath);
      } catch (err) {
        failureCount++;
        console.warn(`::warning::niks3-push: Failed to push ${storePath}: ${err}`);
      }
    }
    if (failureCount > 0) {
      console.warn(`::warning::niks3-push: ${failureCount}/${newPaths.length} paths failed`);
    } else {
      console.log("niks3-push: Push completed successfully");
    }
  } finally {
    await unlink(snapshotPath).catch(() => {});
  }
} catch (err) {
  console.warn(`::warning::niks3-push: ${err}`);
  // post stepの失敗でジョブ全体を失敗させない
}
