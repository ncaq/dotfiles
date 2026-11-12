import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach } from "vitest";

/**
 * テストごとに一時ディレクトリを作る関数を返し、各テストの後に作ったものを消します。
 * `test:watch`を繰り返しても`/tmp`に溜まらないようにするためです。
 */
export function useTempDirs(prefix: string): () => Promise<string> {
  const created: string[] = [];
  afterEach(async () => {
    await Promise.all(created.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
  });
  return async () => {
    const dir = await mkdtemp(path.join(tmpdir(), prefix));
    created.push(dir);
    return dir;
  };
}
