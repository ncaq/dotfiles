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
  `lib/tailnet.nix`を直接importして渡す。

  ```nix
  url = import ../../lib/niks3-private-tailscale-url.nix {
    inherit lib;
    tailnet = config.local.tailscale.tailnet;
  };
  ```
*/
{ lib, tailnet }:
let
  service = import ./niks3-private-tailscale-service.nix;
in
"https://${lib.removePrefix "svc:" service}.${tailnet}/"
