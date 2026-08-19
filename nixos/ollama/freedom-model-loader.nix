# Nix storeのGGUFをOllamaへ登録する。
#
# 1つのモデルは複数のGGUFからなることがあります。
# visionを持つモデルは言語モデル本体とclipの投影器(mmproj)に分かれており、
# `FROM`を並べて書くと`ollama create`が両方を取り込み、
# GGUFのメタデータからどちらが投影器かを判別してレイヤーを分けます。
# 投影器を指定する専用のディレクティブはありません。
#
# ollamaはディレクトリを`FROM`に渡す形も受け付けますが、
# 中身がディレクトリの外を指すsymlinkだと`insecure path`で弾かれるため、
# Nix storeのファイルを`linkFarm`で束ねる形は使えません。
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
    name: sources:
    pkgs.writeText "ollama-${lib.replaceStrings [ ":" ] [ "-" ] name}-Modelfile" (
      lib.concatMapStrings (source: "FROM ${source}\n") sources
    )
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
              name: _sources:
              let
                marker = "${markerDir}/${lib.replaceStrings [ ":" ] [ "-" ] name}";
                # マーカーにはGGUFではなくModelfileのパスを記録します。
                # Modelfileの内容は全てのGGUFのパスを含むので、
                # 構成ファイルが1つでも入れ替われば必ず値が変わります。
                modelfile = toString modelfiles.${name};
              in
              ''
                if [[ ! -f ${lib.escapeShellArg marker} ]] \
                  || [[ $(< ${lib.escapeShellArg marker}) != ${lib.escapeShellArg modelfile} ]] \
                  || ! ollama show ${lib.escapeShellArg name} > /dev/null 2>&1; then
                  ollama create ${lib.escapeShellArg name} --file ${
                    lib.escapeShellArg (toString modelfiles.${name})
                  }
                  printf '%s\n' ${lib.escapeShellArg modelfile} > ${lib.escapeShellArg marker}
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
