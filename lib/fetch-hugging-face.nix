# Hugging Faceのcommit固定リビジョンからファイルを取得する共通関数。
#
# `fetchurl`で`resolve`のURLを引くのではなく`hf download`を使います。
# Xetストレージに載っているリポジトリではファイルがチャンク単位で並列転送されるため、
# 単一のHTTP接続で引くよりGB級のモデルで速くなります。
#
# fixed-output derivationなので、
# `name`と`hash`が同じ限りstoreのパスは`fetchurl`時代から変わりません。
# 取得済みのモデルが再ダウンロードされることはありません。
#
# `HF_TOKEN`が設定されていれば認証付きで取得します(`nixos/core/nix-daemon.nix`)。
# Hugging Faceのレート制限は匿名だとIPアドレス単位でしか枠が無く、
# 多数のモデルをまとめて取得すると429で待たされることがあるためです。
# トークンが無い環境でも公開リポジトリなら取得できるので必須ではありません。
{ pkgs }:
let
  inherit (pkgs) lib;
in
{
  owner,
  repo,
  rev,
  file,
  hash,
}:
pkgs.runCommand (builtins.baseNameOf file)
  {
    nativeBuildInputs = with pkgs; [ python3Packages.huggingface-hub ];

    outputHashMode = "flat";
    outputHash = hash;

    # ビルド環境は隔離されているため、
    # 認証情報とプロキシ設定は明示的に持ち込む必要があります。
    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [ "HF_TOKEN" ];

    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    # Xetの転送並列度を上げます。
    # メモリと帯域を多く使いますが、
    # ダウンロードしかしないビルドなので他の作業を圧迫しません。
    HF_XET_HIGH_PERFORMANCE = "1";
    # プログレスバーは端末ではないビルドログでは更新のたびに行を増やすだけなので消します。
    HF_HUB_DISABLE_PROGRESS_BARS = "1";
    # 起動のたびにPyPIへ新しいバージョンが無いか問い合わせるのを止めます。
    # nixpkgsが固定したバージョンを使う以上、
    # 更新を促されても取れる行動がありません。
    HF_HUB_DISABLE_UPDATE_CHECK = "1";

    # ネットワーク待ちが本体なのでリモートビルダーに投げる意味がありません。
    preferLocalBuild = true;
  }
  ''
    # `hf`はキャッシュとトークンをホームディレクトリ以下に置こうとするため、
    # ビルドディレクトリに閉じ込めます。
    export HOME="$PWD"
    export HF_HOME="$PWD/hf-home"

    # 引数は`escapeShellArg`でクォートします。
    # 呼び出し元はリポジトリ内の固定文字列ですが、
    # Hugging Faceのリポジトリには空白やグロブ文字を含むパスが実在し得るため、
    # 単語分割やパス名展開で別のファイルを取ってしまう事故を防ぎます。
    hf download ${lib.escapeShellArg "${owner}/${repo}"} ${lib.escapeShellArg file} \
      --revision ${lib.escapeShellArg rev} --local-dir dl
    mv ${lib.escapeShellArg "dl/${file}"} "$out"
  ''
