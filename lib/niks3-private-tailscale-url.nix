/**
  niks3-privateのTailscale Service経由のURLを組み立てる関数。

  型: { lib, tailnet } -> String

  Service名は`lib/niks3-private-tailscale-service.nix`が持っている。
  そこからHTTPSのURLを作る手順まで各所で書くと、
  `svc:`を落とす処理とsuffixの付け方が呼び出し側の数だけ散らばるため、
  URLの形はここに集める。

  末尾の`/`は`nixos/core/nix-daemon.nix`の他のsubstituter URLに揃えている。

  NixOSモジュールからは`config.local.tailscale.tailnet`を渡す。
  home-managerから呼ばれるパッケージはNixOSの`config`を読めないため、
  `localLib.tailnet`を渡す。

  使う側は`localLib.niks3PrivateTailscaleUrl`にtailnetを渡して呼ぶ。

  ```nix
  url = localLib.niks3PrivateTailscaleUrl config.local.tailscale.tailnet;
  ```
*/
{ lib, tailnet }:
let
  service = import ./niks3-private-tailscale-service.nix;
in
"https://${lib.removePrefix "svc:" service}.${tailnet}/"
