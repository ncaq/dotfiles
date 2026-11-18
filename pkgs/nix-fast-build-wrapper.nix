# `nix-fast-build`をカスタマイズするラッパ。
# 設定ファイル機能がないので引数を上書きするラッパを作ることでカスタマイズしています。
#
# `--no-link`は、
# チェックするだけで`result`リンクが作成されるのを回避するものです。
# `--skip-cached`は、
# ビルドキャッシュがあるものはスキップして高速化するものです。
#
# 評価のワーカ数は指定しません。
# `nix-fast-build`の既定のCPUスレッド数になります。
# 評価に使うメモリは評価する構成の重さで決まり、このラッパからは分からないので、
# 抑える必要があるリポジトリは自分で`--eval-workers`を渡します。
# このリポジトリは`check.sh`で渡しています。
#
# home-managerの環境と、
# GitHub ActionsのセルフホステッドランナのVMに入れます。
# flakeの`packages`の`nix-fast-build`としても出しているので、
# `./check.sh`はPATHに無い環境でも同じラッパを使います。
{
  writeShellApplication,
  nix-fast-build,
}:
writeShellApplication {
  name = "nix-fast-build";
  runtimeInputs = [ nix-fast-build ];
  text = ''
    exec nix-fast-build \
      --no-link \
      --skip-cached \
      "$@"
  '';
}
