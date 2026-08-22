# Nix storeのGGUFをOllamaへ登録する。
#
# 1つのモデルは複数のGGUFからなることがあります。
# visionを持つモデルは言語モデル本体とclipの投影器(mmproj)に分かれています。
# `FROM`を並べて書くと`ollama create`が全てを取り込み、
# GGUFのメタデータから役割を判別してレイヤーを分けます。
# 投影器を指定する専用のディレクティブはありません。
#
# ただし言語モデル本体として判定されるGGUFは1つに保つ必要があります。
# 2つ以上並べるとollamaは最後の`model`レイヤーを本体として起動し、
# 本体でない方を掴むとllama-serverがsegmentation faultで落ちます。
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
  ggufModels = config.local.ollama.ggufModels;
  markerDir = "${config.local.ollama.dataDir}/gguf-models";
  modelfiles = lib.mapAttrs (
    name: model:
    pkgs.writeText "ollama-${lib.replaceStrings [ ":" ] [ "-" ] name}-Modelfile" (
      lib.concatMapStrings (source: "FROM ${source}\n") model.sources
      # 値は`toJSON`で書きます。
      # 数値はそのまま、文字列は引用符付きになり、
      # Modelfileの`PARAMETER`はどちらの表記も受け付けます。
      + lib.concatStrings (
        lib.mapAttrsToList (key: value: "PARAMETER ${key} ${builtins.toJSON value}\n") model.parameters
      )
    )
  ) ggufModels;
in
{
  containers.ollama.config =
    { config, lib, ... }:
    let
      # loaderの生成はコンテナのモジュール内で完結させる。
      # ホスト側のletから`containers.ollama.config`のパッケージを読んで、
      # 結果を再び同じ`config`へ注入すると評価が往復し、
      # 将来packageが他のコンテナ内オプションに依存したときに無限再帰になりうる。
      # nixpkgsのOllamaモジュールは`loadModels`が空で`syncModels`も無効なら、
      # `ollama-model-loader`を定義しない。
      # 全てのモデルをGGUFから組み立てるホストではpullするものが残らないため、
      # 無条件に依存すると存在しないユニットを要求して起動に失敗する。
      modelLoader = lib.optional (
        config.services.ollama.loadModels != [ ] || config.services.ollama.syncModels
      ) "ollama-model-loader.service";
      loader = pkgs.writeShellApplication {
        name = "ollama-gguf-model-loader";
        runtimeInputs = [ config.services.ollama.package ];
        text = ''
          mkdir -p ${lib.escapeShellArg markerDir}
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              name: _model:
              let
                marker = "${markerDir}/${lib.replaceStrings [ ":" ] [ "-" ] name}";
                # マーカーにはGGUFではなくModelfileのパスを記録します。
                # Modelfileの内容は全てのGGUFのパスとパラメータを含むので、
                # 構成が1つでも入れ替われば必ず値が変わります。
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
            ) ggufModels
          )}
        '';
      };
    in
    {
      systemd.services.ollama-gguf-model-loader = {
        description = "Register declarative GGUF models with Ollama";
        wantedBy = [ "multi-user.target" ];
        requires = modelLoader;
        # Ollamaが起動していなければ`ollama create`は接続に失敗する。
        # `bindsTo`は停止の追従だけで順序は決めないため、`after`も要る。
        after = [ "ollama.service" ] ++ modelLoader;
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
