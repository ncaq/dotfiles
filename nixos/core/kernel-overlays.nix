/**
  全ホスト共通で適用するカーネル関連overlayの登録モジュール。

  CPU最適化overlay(`cpu-optimized-kernel-overlay.nix`)は、
  `local.cpuTarget`が設定されているホストでだけ有効化したいため、
  `cpu-target.nix`の`mkIf`内で別途登録している。
  こちらは適用条件を持たない、
  全ホストで常時必要なoverlayをまとめる。

  サーバ向け派生カーネル`linux_xanmod_server`は、
  実際に`boot.kernelPackages`で参照されない限りビルドコストは発生しない。
  そのためclient向けホストにoverlayを登録しても無害。
*/
_: {
  nixpkgs.overlays = [
    (import ../../lib/xanmod-server-overlay.nix)
  ];
}
