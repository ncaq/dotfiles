# Nix storeのGGUFをOllamaへ登録する。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  freedomModels = config.local.ollama.freedomModels;
  markerDir = "${config.local.ollama.dataDir}/freedom-models";
  modelfiles = lib.mapAttrs (
    name: gguf:
    pkgs.writeText "ollama-${lib.replaceStrings [ ":" ] [ "-" ] name}-Modelfile" ''
      FROM ${gguf}
    ''
  ) freedomModels;
in
{
  containers.ollama.config =
    { config, lib, ... }:
    let
      # loaderの生成はコンテナのモジュール内で完結させる。
      # ホスト側のletから`containers.ollama.config`のパッケージを読んで、
      # 結果を再び同じ`config`へ注入すると評価が往復し、
      # 将来packageが他のコンテナ内オプションに依存したときに無限再帰になりうる。
      loader = pkgs.writeShellApplication {
        name = "ollama-freedom-model-loader";
        runtimeInputs = [ config.services.ollama.package ];
        text = ''
          mkdir -p ${lib.escapeShellArg markerDir}
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              name: gguf:
              let
                marker = "${markerDir}/${lib.replaceStrings [ ":" ] [ "-" ] name}";
              in
              ''
                if [[ ! -f ${lib.escapeShellArg marker} ]] \
                  || [[ $(< ${lib.escapeShellArg marker}) != ${lib.escapeShellArg (toString gguf)} ]] \
                  || ! ollama show ${lib.escapeShellArg name} > /dev/null 2>&1; then
                  ollama create ${lib.escapeShellArg name} --file ${
                    lib.escapeShellArg (toString modelfiles.${name})
                  }
                  printf '%s\n' ${lib.escapeShellArg (toString gguf)} > ${lib.escapeShellArg marker}
                fi
              ''
            ) freedomModels
          )}
        '';
      };
    in
    {
      systemd.services.ollama-freedom-model-loader = {
        description = "Register declarative GGUF models with Ollama";
        wantedBy = [ "multi-user.target" ];
        requires = [ "ollama-model-loader.service" ];
        after = [ "ollama-model-loader.service" ];
        bindsTo = [ "ollama.service" ];
        environment = config.systemd.services.ollama.environment;
        serviceConfig = {
          # oneshotにするとGGUFの登録が終わるまでmulti-user.targetに到達せず、
          # nspawnのready通知が`container@ollama.service`の`TimeoutStartSec`を超えて、
          # 登録の途中でコンテナごとkillされる無限ループに陥る。
          # nixpkgsの`ollama-model-loader`と同じく起動直後にreadyとして扱い、
          # 登録は背後で進める。
          Type = "exec";
          User = "ollama";
          Group = "ollama";
          ExecStart = lib.getExe loader;
          Restart = "on-failure";
          RestartSec = "1s";
          RestartMaxDelaySec = "2h";
          RestartSteps = 10;
        };
      };
    };
}
