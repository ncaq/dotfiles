/**
  OllamaのTailscale Service経由のURLをホスト名から組み立てる関数。

  型: { lib } -> { hostName, tailnet } -> String

  Service名の規則は`lib/ollama-tailscale-service.nix`が持っている。
  そこからHTTPSのURLを作る手順まで各所で書くと、
  `svc:`を落とす処理とsuffixの付け方が呼び出し側の数だけ散らばるため、
  URLの形はここに集める。

  ```nix
  ollamaUrl = import ../../lib/ollama-tailscale-url.nix { inherit lib; };
  url = ollamaUrl {
    hostName = "bullet";
    tailnet = config.local.tailscale.tailnet;
  };
  ```
*/
{ lib }:
{
  hostName,
  tailnet,
}:
let
  service = import ./ollama-tailscale-service.nix hostName;
in
"https://${lib.removePrefix "svc:" service}.${tailnet}"
