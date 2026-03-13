// @ts-check
import { execFile, spawn } from "node:child_process";
import { mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const tempDir = process.env.RUNNER_TEMP || tmpdir();
const SERVER_URL = "https://niks3-public.ncaq.net";

async function getOidcToken() {
  const requestUrl = process.env.ACTIONS_ID_TOKEN_REQUEST_URL;
  const requestToken = process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN;

  if (!requestUrl || !requestToken) {
    throw new Error("OIDC not available (ACTIONS_ID_TOKEN_REQUEST_URL or ACTIONS_ID_TOKEN_REQUEST_TOKEN is not set)");
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

/** JWTのペイロードからexpクレームを取得する。 */
function getJwtExp(/** @type {string} */ jwt) {
  const payload = JSON.parse(Buffer.from(jwt.split(".")[1], "base64url").toString());
  return typeof payload.exp === "number" ? payload.exp : 0;
}

// トークンファイルのキャッシュ。期限が十分残っていれば再利用する。
const TOKEN_MARGIN_SECONDS = 30;
/** @type {string | undefined} */
let tokenDir = undefined;
/** @type {{ tokenFile: string; exp: number } | undefined} */
let cachedToken = undefined;

/** トークンディレクトリを取得する。未作成なら作成する。 */
async function getTokenDir() {
  if (tokenDir == null) {
    tokenDir = await mkdtemp(join(tempDir, "niks3-token-"));
  }
  return tokenDir;
}

/** トークンディレクトリを削除する。 */
async function cleanupTokenDir() {
  if (tokenDir != null) {
    await rm(tokenDir, { recursive: true, force: true }).catch((err) => {
      console.warn(`::warning::niks3-push: Failed to cleanup token directory: ${err}`);
    });
    tokenDir = undefined;
    cachedToken = undefined;
  }
}

/**
 * OIDCトークンファイルのパスをコールバックに渡す。
 * キャッシュ済みトークンの期限が十分残っていれば再利用し、不足していれば新規取得する。
 */
async function withTokenFile(/** @type {(tokenFile: string) => Promise<void>} */ fn) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - now > TOKEN_MARGIN_SECONDS) {
    await fn(cachedToken.tokenFile);
    return;
  }
  const freshToken = await getOidcToken();
  const dir = await getTokenDir();
  const tokenFile = join(dir, "token");
  await writeFile(tokenFile, freshToken, { mode: 0o600 });
  cachedToken = { tokenFile, exp: getJwtExp(freshToken) };
  await fn(tokenFile);
}

/** ストアパスを1件pushする。 */
async function pushStorePath(/** @type {string} */ niks3Bin, /** @type {string} */ storePath) {
  await withTokenFile(async (tokenFile) => {
    await new Promise((resolve, reject) => {
      const child = spawn(`${niks3Bin}/bin/niks3`, ["push", storePath], {
        stdio: ["ignore", "inherit", "inherit"],
        env: {
          ...process.env,
          NIKS3_SERVER_URL: SERVER_URL,
          NIKS3_AUTH_TOKEN_FILE: tokenFile,
        },
      });
      child.on("error", reject);
      child.on("close", (code) => {
        if (code === 0) resolve(undefined);
        else reject(new Error(`niks3 push exited with code ${code}`));
      });
    });
  });
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
    await rm(dirname(snapshotPath), { recursive: true, force: true }).catch(() => {});
    await cleanupTokenDir();
  }
} catch (err) {
  console.warn(`::warning::niks3-push: ${err}`);
  // post stepの失敗でジョブ全体を失敗させない
}
