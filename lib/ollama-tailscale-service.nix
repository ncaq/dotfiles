/**
  OllamaのTailscale Service名をホスト名から組み立てる関数。

  Ollamaは複数のホストがそれぞれ自分のインスタンスを公開するため、
  Service名にホスト名を入れて区別する。

  公開する側と、
  優先順位を付けて接続する側の両方が同じ名前を組み立てる必要がある。
  それぞれにリテラルで書くと、
  規則を変えたときや公開するホストを増減させたときに片方が静かに古いままになる。
  接続先が落ちていても接続がタイムアウトするまで気付けないため、
  規則は1箇所に集める。

  ```nix
  service = import ../../lib/ollama-tailscale-service.nix config.networking.hostName;
  ```
*/
hostName: "svc:ollama-${hostName}"
