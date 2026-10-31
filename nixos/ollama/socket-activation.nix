# ホスト側のsocketへの初回アクセスでOllamaコンテナを起動する。
{
  pkgs,
  config,
  hardening,
  ...
}:
{
  systemd = import ../../lib/container-socket-activation.nix {
    inherit pkgs hardening;
    systemd = config.systemd.package;
    container = "ollama";
    label = "Ollama";
    localAddress = config.containers.ollama.localAddress;
    port = config.containers.ollama.config.services.ollama.port;
    healthPath = "/api/tags";
  };
}
