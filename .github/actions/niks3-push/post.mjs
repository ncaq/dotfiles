// @ts-check
import { execFile } from "node:child_process";
import { readFile, writeFile, unlink } from "node:fs/promises";
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
    throw new Error(
      `OIDC token request failed: ${response.status} ${response.statusText}`,
    );
  }
  const { value } = await response.json();
  return value;
}

try {
  const snapshotPath = process.env.STATE_snapshot_path;
  if (!snapshotPath) {
    console.log("niks3-push: No snapshot found, skipping push");
    process.exit(0);
  }

  // ビルド前後のnix storeの差分を計算
  const prePaths = new Set(
    (await readFile(snapshotPath, "utf-8")).trim().split("\n").filter(Boolean),
  );
  const { stdout: currentPathsOutput } = await execFileAsync(
    "nix",
    ["path-info", "--all"],
    { encoding: "utf-8", maxBuffer: 50 * 1024 * 1024 },
  );
  const currentPaths = currentPathsOutput
    .trim()
    .split("\n")
    .filter(Boolean);
  const newPaths = currentPaths.filter((p) => !prePaths.has(p));

  if (newPaths.length === 0) {
    console.log("niks3-push: No new store paths to push");
    process.exit(0);
  }

  console.log(`niks3-push: Found ${newPaths.length} new store paths to push`);

  const token = await getOidcToken();
  if (!token) process.exit(0);

  // トークンをファイル経由で渡す(プロセスリストへの漏洩防止)
  const tokenFile = join(tempDir, "niks3-oidc-token");
  await writeFile(tokenFile, token, { mode: 0o600 });

  // niks3をビルドしてバイナリパスを取得
  const niks3Ref =
    "git+https://github.com/Mic92/niks3?ref=v1.4.0&rev=bb87dcb1b46a1f0c9426b733f4fe325245e386fa";
  const { stdout: niks3BuildOutput } = await execFileAsync(
    "nix",
    ["build", "--no-link", "--print-out-paths", niks3Ref],
    { encoding: "utf-8" },
  );
  const niks3Bin = niks3BuildOutput.trim();

  // ARG_MAXを回避するためバッチに分割し、並列でpush
  const BATCH_SIZE = 500;
  const batches = Array.from(
    { length: Math.ceil(newPaths.length / BATCH_SIZE) },
    (_, i) => newPaths.slice(i * BATCH_SIZE, (i + 1) * BATCH_SIZE),
  );
  const niks3Env = {
    ...process.env,
    NIKS3_SERVER_URL: SERVER_URL,
    NIKS3_AUTH_TOKEN_FILE: tokenFile,
  };

  try {
    await Promise.all(
      batches.map((batch, i) => {
        console.log(
          `niks3-push: Pushing batch ${i + 1}/${batches.length} (${batch.length} paths)`,
        );
        return execFileAsync(`${niks3Bin}/bin/niks3`, ["push", ...batch], {
          env: niks3Env,
        });
      }),
    );
    console.log("niks3-push: Push completed successfully");
  } finally {
    await unlink(tokenFile).catch(() => {});
  }
} catch (err) {
  console.error("niks3-push:", err);
  // post stepの失敗でジョブ全体を失敗させない
}
