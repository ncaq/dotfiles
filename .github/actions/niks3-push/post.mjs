// @ts-check
import { execFileSync } from "node:child_process";
import { readFile, writeFile, unlink } from "node:fs/promises";

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
  const currentPaths = execFileSync("nix", ["path-info", "--all"], {
    encoding: "utf-8",
  })
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
  const tokenFile = "/tmp/niks3-oidc-token";
  await writeFile(tokenFile, token, { mode: 0o600 });

  try {
    execFileSync(
      "nix",
      [
        "run",
        "git+https://github.com/Mic92/niks3?ref=v1.4.0&rev=bb87dcb1b46a1f0c9426b733f4fe325245e386fa",
        "--",
        "push",
        ...newPaths,
      ],
      {
        stdio: "inherit",
        env: {
          ...process.env,
          NIKS3_SERVER_URL: SERVER_URL,
          NIKS3_AUTH_TOKEN_FILE: tokenFile,
        },
      },
    );
    console.log("niks3-push: Push completed successfully");
  } finally {
    await unlink(tokenFile).catch(() => {});
  }
} catch (err) {
  console.error("niks3-push:", err);
  // post stepの失敗でジョブ全体を失敗させない
}
