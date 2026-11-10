/**
  Garage S3バケットとキーのセットアップサービスを生成する関数。
  niks3-public, niks3-privateなど、Garageバケットを使うサービスで共用する。
  起動時にidempotentにS3キーを作成し、バケットに権限を付与する。
  キーは使い捨てであり、起動時ごとに新しいキーが生成されます。
  古いキーは触らず捨てて期限切れを待ちます。
  古いキーが蓄積するのは問題にならないと想定しています。
*/
{
  pkgs,
  config,
  inputs,
  name,
}:
let
  hardening = import ./systemd-hardening.nix;
in
{
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
    ExecStart = pkgs.lib.getExe (
      pkgs.callPackage ../pkgs/garage-setup { inherit (inputs) himari-src; }
    );
  };
  # 環境変数の意味は`pkgs/garage-setup/src/GarageSetup/Config.hs`に書いてあります。
  # キーファイルの書き出し先は`RuntimeDirectory`からsystemdが`RUNTIME_DIRECTORY`として渡します。
  environment = {
    GARAGE_SETUP_NAME = name;
    GARAGE_SETUP_API = "http://${config.machineAddresses.garage.guest}:3903";
    GARAGE_SETUP_ADMIN_TOKEN_FILE = config.sops.secrets."garage-admin-token".path;
  };
}
