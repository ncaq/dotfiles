// @ts-check
import { readdir } from "node:fs/promises";
import { join } from "node:path";

const NIX_STORE = "/nix/store";

/** /nix/store内のパスを列挙する。.drv等は除外する。 */
export async function listStorePaths() {
  const entries = await readdir(NIX_STORE);
  return entries
    .filter((e) => !e.endsWith(".drv") && !e.endsWith(".drv.chroot") && !e.endsWith(".check") && !e.endsWith(".lock"))
    .map((e) => join(NIX_STORE, e));
}
