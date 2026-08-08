# Nix storeのGGUFをOllamaへ登録する。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ollama = config.containers.ollama.config.services.ollama;
  freedomModels = config.local.ollama.freedomModels;
  markerDir = "/var/lib/ollama/freedom-models";
  modelfiles = lib.mapAttrs (
    name: gguf:
    pkgs.writeText "ollama-${lib.replaceStrings [ ":" ] [ "-" ] name}-Modelfile" ''
      FROM ${gguf}
    ''
  ) freedomModels;
  loader = pkgs.writeShellApplication {
    name = "ollama-freedom-model-loader";
    runtimeInputs = [ ollama.package ];
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
  containers.ollama.config =
    { config, lib, ... }:
    {
      systemd.services.ollama-freedom-model-loader = {
        description = "Register declarative GGUF models with Ollama";
        wantedBy = [ "multi-user.target" ];
        requires = [ "ollama-model-loader.service" ];
        after = [ "ollama-model-loader.service" ];
        bindsTo = [ "ollama.service" ];
        environment = config.systemd.services.ollama.environment;
        serviceConfig = {
          Type = "oneshot";
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
