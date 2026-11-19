# コーディングエージェント用の一時作業ディレクトリを用意するモジュール。
# ディレクトリを作成して、
# そのパスを`codingAgentWorkDirFullPath`として他のモジュールへ渡します。
{
  username,
  osConfig ? null,
  ...
}:
let
  # 作業ディレクトリの名前。
  # 渡すパスと作るディレクトリが食い違わないように、ここだけで決めます。
  dirName = "coding-agent-work";
  # konokaプラグインは`${XDG_RUNTIME_DIR:-/tmp}/coding-agent-work/`を使用します。
  # NixOS環境では`osConfig`からUIDを取得し、非NixOS環境では`/tmp`へフォールバックします。
  # この仕様は調査した上で変更する予定です。
  # どう変更するかの詳細はまだ決まっていません。
  codingAgentWorkDirFullPath =
    let
      uid = if osConfig != null then osConfig.users.users.${username}.uid else null;
      base = if uid != null then "/run/user/${toString uid}" else "/tmp";
    in
    "${base}/${dirName}/";
in
{
  _module.args = { inherit codingAgentWorkDirFullPath; };
  # コーディングエージェントが使うスキル用の一時作業ディレクトリを作成します。
  # 各スキルなどは明示的にディレクトリを最初に作成するようにしていますが、
  # 念の為に事前にディレクトリを作成しておきます。
  # `%t`はユーザtmpfilesでは`$XDG_RUNTIME_DIR`に展開されます。
  # `$XDG_RUNTIME_DIR`はログアウト時に消滅するため、
  # クリーンアップ期間はデフォルトに任せます。
  # `/tmp`の方にフォールバックされたとしても、
  # デフォルトではOSが10日でクリーンアップするので、
  # 大きな問題にはなりません。
  # tmpをクリーンアップしないOSはサポート外です。
  systemd.user.tmpfiles.rules = [
    "d %t/${dirName} 0700 - -"
  ];
}
