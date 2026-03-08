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
  # `lastModifiedDate`は"20260308123456"形式。ISO 8601に変換します。
  d = inputs.self.lastModifiedDate or "00000000000000";
  isoDateTime = "${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}T${builtins.substring 8 2 d}:${builtins.substring 10 2 d}:${builtins.substring 12 2 d}";
  # コミットリビジョン。
  # `install.sh`が`last-commit`をstagingするため必ずdirtyになります。
  # "-dirty"サフィックスは自前の注入によるものなので除去します。
  shortRev = lib.strings.removeSuffix "-dirty" inputs.self.dirtyShortRev;
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
  dirtySuffix = if isDirty then "-dirty" else "";
  # conventional commitsのtype(scope)をパースしてラベルに使います。
  # 例: "fix(boot): message" → "fix.boot", "feat: message" → "feat"
  parsed =
    if lastCommitSubject != null then
      builtins.match "([a-zA-Z]+)(\\(([a-zA-Z0-9._-]+)\\))?: *(.*)" lastCommitSubject
    else
      null;
  commitType = if parsed != null then builtins.elemAt parsed 0 else null;
  commitScope = if parsed != null then builtins.elemAt parsed 2 else null;
  commitLabel =
    if commitType != null && commitScope != null then
      "${commitType}.${commitScope}"
    else if commitType != null then
      commitType
    else
      "unknown";
in
{
  system.nixos.label = "${isoDateTime}-${config.system.nixos.release}-${shortRev}${dirtySuffix}-${commitLabel}";
}
