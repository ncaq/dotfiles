/**
  garageのバケットを使うコンテナの定型を、
  `containers.<name>.local.garageBucket`の宣言から生成する。

  コンテナと同じ名前のバケットとS3のキーを`garage-setup-<name>.service`が用意して、
  キーを`/run/garage-setup/<name>/s3-access-key`と`s3-secret-key`へ書き出す。
  その2つのファイルをコンテナへ同じパスで読み取り専用で渡し、
  キーが書き出されてからコンテナを起動する。

  `garage-setup-<name>.service`は起動のたびにidempotentにキーを作って、バケットに権限を付与する。
  キーは使い捨てで、起動のたびに新しいキーが生成される。
  古いキーは触らず捨てて期限切れを待つ。
  古いキーが蓄積するのは問題にならないと想定している。

  キーのファイルはコンテナと同じ名前のユーザの所有になるので、
  `local.serviceUser`も有効にして、ホストにもそのユーザを作る。

  garageへ繋ぐ経路はコンテナごとに違うので、
  `local.machineEgress`などの宣言は個々のコンテナの定義に残す。
*/
{
  lib,
  pkgs,
  config,
  hardening,
  ...
}:
let
  setupOf = name: {
    description = "Setup Garage bucket and key for ${name}";
    requires = [ "container@garage.service" ];
    after = [ "container@garage.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = hardening.network // {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "garage-setup/${name}";
      RuntimeDirectoryMode = "0700";
      # 生成したキーファイルをクライアントユーザへchownするために必要なcapabilityだけ許可する。
      CapabilityBoundingSet = [
        "CAP_CHOWN"
        "CAP_DAC_READ_SEARCH"
        "CAP_FOWNER"
      ];
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "@chown"
      ];
      ExecStart = lib.getExe pkgs.garage-setup;
    };
    # 環境変数の意味は`pkgs/garage-setup/src/GarageSetup/Config.hs`に書いてあります。
    # キーファイルの書き出し先は`RuntimeDirectory`からsystemdが`RUNTIME_DIRECTORY`として渡します。
    environment = {
      GARAGE_SETUP_NAME = name;
      GARAGE_SETUP_API = "http://[${config.machineAddresses.garage.guest6}]:3903";
      GARAGE_SETUP_ADMIN_TOKEN_FILE = config.sops.secrets."garage-admin-token".path;
    };
  };
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

          config = lib.mkIf config.local.garageBucket {
            local.serviceUser = true;
            bindMounts = lib.genAttrs (keyFiles name) (path: {
              hostPath = path;
              isReadOnly = true;
            });
          };
        }
      )
    );
  };

  config.systemd.services = lib.mkMerge (
    map (name: {
      "garage-setup-${name}" = setupOf name;
      "container@${name}" = {
        requires = [ "garage-setup-${name}.service" ];
        after = [ "garage-setup-${name}.service" ];
      };
    }) clients
  );
}
