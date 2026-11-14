/**
  ブートエントリのラベルにdotfilesのコミット情報を含めます。
  デフォルトでは乏しい情報しかないため、
  どのdotfilesコミットでビルドされたか識別が難しいためです。
*/
{
  lib,
  config,
  inputs,
  ...
}:
let
  # コミットリビジョン。
  # `install.sh`が呼ぶ`pkgs/dotfiles-install`が、
  # 最後のコミット情報ファイルをstagingするため必ずdirtyになります。
  # "-dirty"サフィックスは自前の注入によるものなので除去します。
  shortRev =
    lib.strings.removeSuffix "-dirty"
      inputs.self.dirtyShortRev or inputs.self.shortRev or "nothing-rev";
  # `dotfiles-install`が最新コミットの情報を`last-commit.json`に保存してstagingします。
  # 形は`pkgs/dotfiles-install/src/DotfilesInstall/LastCommit.hs`と揃えます。
  lastCommitFile = "${inputs.self}/last-commit.json";
  lastCommit =
    if builtins.pathExists lastCommitFile then
      builtins.fromJSON (builtins.readFile lastCommitFile)
    else
      null;
  lastCommitSubject = if lastCommit != null then lastCommit.subject else null;
  # `dotfiles-install`が注入前に記録した本来のdirty状態。
  dirtySuffix = if lastCommit != null && lastCommit.dirty then "-dirty" else "";
  # `dotfiles-install`が記録したブランチ名。
  branchLabel =
    if lastCommit != null && lastCommit.branch != "" then
      "-${builtins.replaceStrings [ "/" ] [ "." ] lastCommit.branch}"
    else
      "-missing-branch";
  # コミットsubjectからラベルを生成します。
  # conventional commits: "fix(boot): message" → "fix.boot", "feat: message" → "feat"
  # GitHubマージ: "Merge pull request #717 from ncaq/branch-name" → "merge.branch-name"
  conventionalParsed =
    if lastCommitSubject != null then
      builtins.match "([a-zA-Z]+)(\\(([a-zA-Z0-9._-]+)\\))?: *(.*)" lastCommitSubject
    else
      null;
  mergeParsed =
    if lastCommitSubject != null then
      builtins.match "Merge pull request #([0-9]+) from [^/]+/(.*)" lastCommitSubject
    else
      null;
  commitLabel =
    if conventionalParsed != null then
      let
        commitType = builtins.elemAt conventionalParsed 0;
        commitScope = builtins.elemAt conventionalParsed 2;
      in
      if commitScope != null then "${commitType}.${commitScope}" else commitType
    else if mergeParsed != null then
      "merge.${builtins.replaceStrings [ "/" ] [ "." ] (builtins.elemAt mergeParsed 1)}"
    else
      "unknown";
  inherit (config.system.nixos) release;
in
{
  system.nixos.label = "${release}-${shortRev}${dirtySuffix}${branchLabel}-${commitLabel}";
}
