/**
 * 復旧のClaude Codeの`permissions.deny`のうち、
 * `Edit`の規則が意図した場所だけを拒否しているかを判定する規則。
 *
 * `deny`は`allow`より優先されるので、
 * 作業ツリーを覆う拒否が入ると、Claude Codeは結果のファイルも修正も書けなくなります。
 * その時もワークフローは成功で終わるので、復旧が要る時まで気付けません。
 * 逆に、後のステップが読む場所の拒否が消えても気付けません。
 * セルフホステッドランナーと同じ配置を仮定して、両方を確かめます。
 *
 * Claude Codeの規則の照合をそのまま再現するものではありません。
 * このリポジトリが使っている3つの書き方だけを扱い、
 * 知らない書き方は見逃さないよう問題として報告します。
 *
 * - `//`で始まる: ファイルシステムの絶対パス
 * - `~/`で始まる: ホームディレクトリからのパス
 * - `./`で始まる: 作業ディレクトリからのパス
 *
 * ファイルシステムに触れない判定だけをここに置いて、テストできるようにしています。
 */

/** 規則を当てはめるランナーの配置。 */
export interface RunnerLayout {
  /** ホームディレクトリ。 */
  readonly home: string;
  /** Claude Codeの作業ディレクトリ。 */
  readonly cwd: string;
}

/** nixpkgsのgithub-runnerのモジュールが、ランナーごとの作業ディレクトリを置く場所。 */
const RUNNER_ROOT = "/run/github-runner";

/**
 * ランナーのホームディレクトリを返します。
 * nixpkgsのgithub-runnerのモジュールは、
 * `HOME`とランナーの作業ディレクトリを`/run/github-runner/<ランナーの名前>`にします。
 */
function runnerHome(name: string): string {
  return `${RUNNER_ROOT}/${name}`;
}

/**
 * セルフホステッドランナーの配置。
 * ランナーの名前は`nixos/host/seminar/github-runner/github-runner-x64.nix`が決めています。
 * 作業ツリーをホームディレクトリの下の`<リポジトリ名>/<リポジトリ名>`に置くのは、
 * nixpkgsのモジュールではなく、Actionsのランナーと`actions/checkout`の既定の動きです。
 */
export const RUNNER_LAYOUT: RunnerLayout = {
  home: runnerHome("dotfiles-x64-0"),
  cwd: `${runnerHome("dotfiles-x64-0")}/dotfiles/dotfiles`,
};

/** Claude Codeが書けなければならない、作業ディレクトリからのパス。 */
export const MUST_BE_WRITABLE: readonly string[] = [
  ".renovate-recovery/result.md",
  ".renovate-recovery/pr-body.md",
  "flake.lock",
  "pkgs/renovate-recovery/package-lock.json",
];

/** Claude Codeが書けてはならない絶対パス。 */
export const MUST_BE_DENIED: readonly string[] = [
  `${RUNNER_LAYOUT.cwd}/.git/config`,
  `${RUNNER_LAYOUT.cwd}/check.sh`,
  `${RUNNER_LAYOUT.cwd}/.github/workflows/check.yml`,
  `${RUNNER_LAYOUT.home}/_temp/renovate-recovery-src/post-comment.ts`,
  `${RUNNER_LAYOUT.home}/_actions/actions/github-script/v9/dist/index.js`,
  `${RUNNER_LAYOUT.home}/_tool/node/bin/node`,
  `${RUNNER_LAYOUT.home}/.gitconfig`,
  `${RUNNER_LAYOUT.home}/.config/git/config`,
  // 同じVMで動く他のランナーの、後のステップが読む場所。
  `${runnerHome("dotfiles-x64-1")}/_temp/set_env`,
];

/** `Edit(...)`の規則ならその中身を返します。他のツールの規則なら`undefined`です。 */
export function editRulePattern(rule: string): string | undefined {
  return /^Edit\((?<pattern>.*)\)$/su.exec(rule)?.groups?.["pattern"];
}

/**
 * `Edit`の規則の中身を、絶対パスのglobにします。
 * 知らない書き方なら`undefined`を返します。
 */
export function resolveEditPattern(pattern: string, layout: RunnerLayout): string | undefined {
  if (pattern.startsWith("//")) {
    return pattern.slice(1);
  }
  if (pattern.startsWith("~/")) {
    return `${layout.home}/${pattern.slice(2)}`;
  }
  if (pattern.startsWith("./")) {
    return `${layout.cwd}/${pattern.slice(2)}`;
  }
  return undefined;
}

/**
 * globをパスの全体に当てる正規表現にします。
 * `**`は階層をまたいで何にでも、`*`は1つの階層の中で何にでも当たります。
 *
 * `path.matchesGlob`は使いません。
 * `.`で始まる名前に`*`や`**`が当たらないので、
 * `Edit(~/**)`が`.renovate-recovery/`を覆うことを見逃すからです。
 * Claude Codeの規則はgitignoreと同じく`.`で始まる名前にも当たります。
 */
export function globToRegExp(glob: string): RegExp {
  const source = glob
    .split("**")
    .map((part) =>
      part
        .split("*")
        .map((literal) => literal.replaceAll(/[\\^$.+?()[\]{}|]/gu, String.raw`\$&`))
        .join("[^/]*"),
    )
    .join(".*");
  return new RegExp(`^${source}$`, "su");
}

/** 絶対パスに当たる`Edit`の拒否の規則を返します。 */
export function findDenyingRules(
  denyRules: readonly string[],
  layout: RunnerLayout,
  target: string,
): string[] {
  return denyRules.filter((rule) => {
    const pattern = editRulePattern(rule);
    const glob = pattern == null ? undefined : resolveEditPattern(pattern, layout);
    return glob != null && globToRegExp(glob).test(target);
  });
}

/**
 * `permissions.deny`の一覧を調べて、見つけた問題を返します。
 * 問題が無ければ空の配列です。
 */
export function checkEditDenyRules(denyRules: readonly string[]): string[] {
  const unknown = denyRules.flatMap((rule) => {
    const pattern = editRulePattern(rule);
    return pattern != null && resolveEditPattern(pattern, RUNNER_LAYOUT) == null
      ? [`${rule} は判定できない書き方です`]
      : [];
  });
  const overDenied = MUST_BE_WRITABLE.flatMap((relative) =>
    findDenyingRules(denyRules, RUNNER_LAYOUT, `${RUNNER_LAYOUT.cwd}/${relative}`).map(
      (rule) => `${rule} が作業ツリーの ${relative} への書き込みを拒否しています`,
    ),
  );
  const underDenied = MUST_BE_DENIED.flatMap((target) =>
    findDenyingRules(denyRules, RUNNER_LAYOUT, target).length === 0
      ? [`${target} への書き込みを拒否する規則がありません`]
      : [],
  );
  return [...unknown, ...overDenied, ...underDenied];
}
