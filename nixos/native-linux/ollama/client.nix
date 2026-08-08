# コンテナ内のOllamaへ接続するCLIをホストから利用可能にする。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ollama = config.containers.ollama.config.services.ollama;
  ollama-client = pkgs.writeShellApplication {
    name = "ollama";
    runtimeEnv.OLLAMA_HOST = "127.0.0.1:${toString ollama.port}";
    text = ''
      exec ${lib.getExe ollama.package} "$@"
    '';
  };
in
{
  environment.systemPackages = [ ollama-client ];
}
