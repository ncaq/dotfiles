/**
  garageのバケットを使うコンテナの定型を、
  `containers.<name>.local.garageBucket`の宣言から生成する。

  コンテナと同じ名前のバケットとS3のキーを`garage-setup-<name>.service`(`lib/garage-setup.nix`)が用意して、
  キーを`/run/garage-setup/<name>/s3-access-key`と`s3-secret-key`へ書き出す。
  その2つのファイルをコンテナへ同じパスで読み取り専用で渡し、
  キーが書き出されてからコンテナを起動する。

  キーのファイルはコンテナと同じ名前のユーザの所有になるので、
  `local.serviceUser`でホストにもそのユーザを作っておく必要がある。

  garageへ繋ぐ経路はコンテナごとに違うので、
  `local.machineEgress`などの宣言は個々のコンテナの定義に残す。
*/
{
  lib,
  pkgs,
  config,
  ...
}:
let
  keyFiles = name: [
    "/run/garage-setup/${name}/s3-access-key"
    "/run/garage-setup/${name}/s3-secret-key"
  ];
  clients = lib.attrNames (lib.filterAttrs (_: c: c.local.garageBucket) config.containers);
in
{
  options.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          options.local.garageBucket = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "コンテナと同じ名前のgarageのバケットとS3のキーを用意して、キーをコンテナへ渡すか。";
          };

          config.bindMounts = lib.mkIf config.local.garageBucket (
            lib.genAttrs (keyFiles name) (path: {
              hostPath = path;
              isReadOnly = true;
            })
          );
        }
      )
    );
  };

  config = {
    systemd.services = lib.mkMerge (
      map (name: {
        "garage-setup-${name}" = import ../../../lib/garage-setup.nix { inherit pkgs config name; };
        "container@${name}" = {
          requires = [ "garage-setup-${name}.service" ];
          after = [ "garage-setup-${name}.service" ];
        };
      }) clients
    );

    assertions = [
      (
        let
          userless = lib.filter (name: !config.containers.${name}.local.serviceUser) clients;
        in
        {
          assertion = userless == [ ];
          message = "containers.<name>.local.garageBucket: キーのファイルの所有者になるユーザが要るので`local.serviceUser`も有効にしてください: ${lib.concatStringsSep ", " userless}";
        }
      )
    ];
  };
}
