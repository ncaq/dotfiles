import type * as core from "@actions/core";
import type { context, getOctokit } from "@actions/github";

/**
 * `actions/github-script`がスクリプトへ注入する値のうち、ここで使うもの。
 *
 * これらのパッケージは型のためだけに入れています。
 * 実行時にはgithub-scriptが同梱しているものが渡されるので、`import type`でしか読み込みません。
 */
export interface ScriptArguments {
  /** 認証済みのoctokitのクライアント。 */
  readonly github: ReturnType<typeof getOctokit>;
  /** ワークフローの実行の文脈。 */
  readonly context: typeof context;
  /** ジョブの出力やログを扱う関数群。 */
  readonly core: typeof core;
}
