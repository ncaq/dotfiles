// @ts-check
import { readdir } from "node:fs/promises";
import { join } from "node:path";

const NIX_STORE = "/nix/store";

/** Nix store pathの標準形式: <32文字のnix base32ハッシュ>-<名前>(末尾が.drvや.drv.chroot等でない) */
const STORE_PATH_RE = /^[0-9a-df-np-sv-z]{32}-.+(?<!\.drv)(?<!\.drv\.chroot)(?<!\.check)(?<!\.lock)$/;

/** /nix/store内の正規のストアパスのみを列挙する。 */
export async function listStorePaths() {
  const entries = await readdir(NIX_STORE);
  return entries.filter((e) => STORE_PATH_RE.test(e)).map((e) => join(NIX_STORE, e));
}
