# baseとPRのNix評価結果をnvdで比べて、差分をPRコメントとして投稿するコマンド。
#
# `.github/workflows/check.yml`の`nvd-diff`ジョブが`nix run .#nvd-pr-diff`で呼ぶ。
# 入力は全て環境変数で、何が要るかは`src/NvdPrDiff/Target.hs`に書いてある。
# nvdの出力をどう読むかは`src/NvdPrDiff/Report.hs`に、
# コメントの形は`src/NvdPrDiff/Markdown.hs`にある。
#
# `callPackage`の結果に`haskell.lib`の関数を重ねると、
# `override`がこのファイルを`mkDerivation`付きで呼び直して壊れる。
# CIで警告をエラーにしたい時は`werror`で指定する。
{
  lib,
  haskell,
  haskellPackages,
  makeWrapper,
  git,
  nix,
  nvd,
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
      ./nvd-pr-diff.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "nvd-pr-diff" source { };
in
lib.pipe package [
  (haskell.lib.compose.overrideCabal (old: {
    buildTools = (old.buildTools or [ ]) ++ [ makeWrapper ];
    # 評価と比較は外部コマンドに任せるので、PATHへ足して包む。
    # GitHubへの投稿は自前でHTTPを叩くので`gh`は要らない。
    postInstall = (old.postInstall or "") + ''
      wrapProgram "$out/bin/nvd-pr-diff" \
        --prefix PATH : ${
          lib.makeBinPath [
            git
            nix
            nvd
          ]
        }
    '';
  }))
  (haskell.lib.compose.appendConfigureFlags (lib.optional werror "--ghc-options=-Werror"))
  haskell.lib.compose.justStaticExecutables
]
