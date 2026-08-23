/**
  ComfyUIのTailscale Service名。

  公開する側と、
  tailnetの外から中継して接続する側の両方が同じ名前を必要とする。
  それぞれにリテラルで書くと、
  名前を変えたときに片方が静かに古いままになる。
  接続先が落ちている場合と区別が付かず、
  接続がタイムアウトするまで気付けないため、
  名前は1箇所に集める。

  Ollamaと違ってComfyUIを公開するのはGPUを持つホストだけなので、
  `lib/ollama-tailscale-service.nix`のようにホスト名は取らない。

  ```nix
  service = import ../../../../lib/comfyui-tailscale-service.nix;
  ```
*/
"svc:comfyui"
