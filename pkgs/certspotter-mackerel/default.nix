# certspotterが検知したイベントをMackerelのチェックへ繋ぐコマンド。
#
# 1つのコマンドに2つのサブコマンドを持つ。
#
# - `certspotter-mackerel hook`: certspotterのhookとして、イベントを1行のJSONでログへ追記する
# - `certspotter-mackerel check`: Mackerelのチェックとして、ログに最近のイベントがあればWARNINGかCRITICALにする
#
# `nixos/host/seminar/certspotter.nix`が設定の環境変数を付けたラッパーで包んで使う。
# 入力は全て環境変数で、何が要るかは`src/CertspotterMackerel/Config.hs`と
# `src/CertspotterMackerel/Notification.hs`に書いてある。
#
# シェルではなくHaskellで書いている。
# `SUMMARY`や`ISSUER_DN`やSANはCAとCTログ由来の信頼できない値で、
# シェルで制御文字を潰すだけでは漏れが出やすいためである。
# aesonに記録と読み取りの両方を任せれば、
# 改行やタブが入っても列ずれや偽の行は構造的に起きない。
#
# `callPackage`の結果に`haskell.lib`の関数を重ねると、
# `override`がこのファイルを`mkDerivation`付きで呼び直して壊れる。
# CIで警告をエラーにしたい時は`werror`で指定する。
{
  lib,
  haskell,
  haskellPackages,
  himari-src,
  werror ? false,
}:
let
  packages = haskellPackages.extend (
    hself: _hsuper: {
      # himariはstableのnixpkgsではbrokenなので、上流のソースから組む。
      himari = hself.callCabal2nix "himari" himari-src { };
    }
  );
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
  package = packages.callCabal2nix "certspotter-mackerel" source { };
in
lib.pipe package [
  (haskell.lib.compose.appendConfigureFlags (lib.optional werror "--ghc-options=-Werror"))
  # seminarの閉包へGHCを持ち込まない。
  haskell.lib.compose.justStaticExecutables
]
