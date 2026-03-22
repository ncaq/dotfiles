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
  # `install.sh`が最新コミットのsubjectとdirty状態を`last-commit`ファイルに保存してstagingします。
  # 1行目: コミットsubject、2行目: clean/dirty(注入前の本来の状態)
  lastCommitFile = "${inputs.self}/last-commit";
  lastCommitLines =
    if builtins.pathExists lastCommitFile then
      lib.splitString "\n" (builtins.readFile lastCommitFile)
    else
      null;
  lastCommitSubject = if lastCommitLines != null then builtins.elemAt lastCommitLines 0 else null;
  # install.shが注入前に記録した本来のdirty状態。
  isDirty =
    if lastCommitLines != null && builtins.length lastCommitLines >= 2 then
      builtins.elemAt lastCommitLines 1 == "dirty"
    else
      false;
  dirtySuffix = if isDirty then "-dirty-" else "";
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
in
{
  system.nixos.label = "${time}-${config.system.nixos.release}-${shortRev}${dirtySuffix}${commitLabel}";
}
