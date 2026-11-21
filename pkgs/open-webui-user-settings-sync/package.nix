# Open WebUIの利用者ごとの設定とプロフィールを、宣言した内容へ揃えるコマンド。
#
# `nixos/host/seminar/open-webui/user-settings.nix`のサービスから呼ばれる。
# 何をするかは`src/UserSettingsSync/Sync.hs`に、
# 入力の環境変数は`src/UserSettingsSync/Config.hs`に書いてある。
#
# Open WebUIのAPIは自前でHTTPを叩くので、外部コマンドへの依存は無い。
{
  lib,
  haskell,
  localHaskellPackages,
}:
let
  # 動かすものだけをstoreへ入れる。
  # ディレクトリをそのまま渡すと`dist-newstyle`のような作業中のファイルまで付いてくる。
  source = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./open-webui-user-settings-sync.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = localHaskellPackages.callCabal2nix "open-webui-user-settings-sync" source { };
in
lib.pipe package [
  # seminarのクロージャへGHCを持ち込まない。
  haskell.lib.compose.justStaticExecutables
]
