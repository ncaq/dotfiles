/**
  niks3-privateのTailscale Service名。

  公開する側のseminarと、
  substituterやアップロード先として接続する側の両方が同じ名前を必要とする。
  それぞれにリテラルで書くと、
  名前を変えたときに片方が静かに古いままになる。
  接続先が落ちている場合と区別が付かず、
  接続がタイムアウトするまで気付けないため、
  名前は1箇所に集める。

  公開するのは常時起動のseminarだけなので、
  `lib/ollama-tailscale-service.nix`のようにホスト名は取らない。

  URLの形は`lib/niks3-private-tailscale-url.nix`が持っている。

  ```nix
  service = import ../../../lib/niks3-private-tailscale-service.nix;
  ```
*/
"svc:niks3-private"
