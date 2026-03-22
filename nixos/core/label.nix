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
  # `lastModifiedDate`は"20260308123456"形式。日付は他で表示されるため時刻部分のみ使用します。
  d = inputs.self.lastModifiedDate or "00000000000000";
  time = "${builtins.substring 8 2 d}:${builtins.substring 10 2 d}:${builtins.substring 12 2 d}";
  # コミットリビジョン。
  # `install.sh`が`last-commit`をstagingするため必ずdirtyになります。
  # "-dirty"サフィックスは自前の注入によるものなので除去します。
  shortRev = lib.strings.removeSuffix "-dirty" inputs.self.dirtyShortRev or inputs.self.shortRev;
  # `install.sh`が最新コミットの情報を`last-commit.nix`に保存してstagingします。
  lastCommitFile = "${inputs.self}/last-commit.nix";
  lastCommit = if builtins.pathExists lastCommitFile then import lastCommitFile else null;
  lastCommitSubject = if lastCommit != null then lastCommit.subject else null;
  # install.shが注入前に記録した本来のdirty状態。
  dirtySuffix = if lastCommit != null && lastCommit.dirty then "-dirty" else "";
  # install.shが記録したブランチ名。
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
      "-merge.${builtins.replaceStrings [ "/" ] [ "." ] (builtins.elemAt mergeParsed 1)}"
    else
      "-unknown";
in
{
  system.nixos.label = "${time}-${config.system.nixos.release}-${shortRev}${dirtySuffix}${branchLabel}${commitLabel}";
}
