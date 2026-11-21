# certspotterが検知したイベントをMackerelのチェックへ繋ぐコマンド。
#
# 1つのコマンドに2つのサブコマンドを持つ。
#
# - `certspotter-mackerel hook`: certspotterのhookとして、イベントを1行のJSONでログへ追記する
# - `certspotter-mackerel check`: Mackerelのチェックとして、ログに最近のイベントがあればWARNINGかCRITICALにする
#
# `nixos/host/seminar/certspotter.nix`が設定の環境変数を付けたラッパで包んで使う。
# 入力は全て環境変数で、何が要るかは`src/CertspotterMackerel/Config.hs`と
# `src/CertspotterMackerel/Notification.hs`に書いてある。
#
# シェルではなくHaskellで書いている。
# `SUMMARY`や`ISSUER_DN`やSANはCAとCTログ由来の信頼できない値で、
# シェルで制御文字を潰すだけでは漏れが出やすいためである。
# aesonに記録と読み取りの両方を任せれば、
# 改行やタブが入っても列ずれや偽の行は構造的に起きない。
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
      ./certspotter-mackerel.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = localHaskellPackages.callCabal2nix "certspotter-mackerel" source { };
in
lib.pipe package [
  # seminarのクロージャへGHCを持ち込まない。
  haskell.lib.compose.justStaticExecutables
]
