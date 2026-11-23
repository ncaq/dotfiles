{
  config,
  pkgs,
  ...
}:
let
  # ホストからコンテナ内のforgejoコマンドを実行するラッパスクリプト
  forgejoWrapper = pkgs.writeShellApplication {
    name = "forgejo";
    runtimeInputs = with pkgs; [ nixos-container ];
    text = ''
      exec nixos-container run forgejo -- forgejo "$@"
    '';
  };
  garageAddr = config.machineAddresses.garage.guest6;
in
{
  containers.forgejo = {
    local = {
      postgres = true;
      # LFSオブジェクトをgarage(S3互換)に保存します。
      garageBucket = true;
      persist = [ "/var/lib/forgejo" ];
    };
    forwardPorts = [
      {
        containerPort = 2222;
        hostPort = 2222;
        protocol = "tcp";
      }
    ];
    config =
      { config, ... }:
      {
        networking.firewall.allowedTCPPorts = [
          2222 # ssh
          8080 # http
        ];
        services.forgejo = {
          enable = true;
          # LFSサーバ機能(`LFS_START_SERVER`)を有効化し、
          # `LFS_JWT_SECRET`も自動生成します。
          # 保存先は下の`settings.lfs`でminio(garage)に切り替えます。
          lfs.enable = true;
          database = {
            type = "postgres";
            # PostgreSQLは直接接続されないため、
            # NixOSによるデータベース自動生成機能は無効にします。
            createDatabase = false;
            socket = "/run/postgresql";
          };
          settings = {
            server = {
              HTTP_PORT = 8080;
              SSH_PORT = 2222;
              DOMAIN = "forgejo.ncaq.net";
              ROOT_URL = "https://forgejo.ncaq.net/";
              SSH_DOMAIN = "ssh.forgejo.ncaq.net";
              START_SSH_SERVER = true;
            };
            session = {
              COOKIE_SECURE = true;
            };
            service = {
              DISABLE_REGISTRATION = true;
            };
            repository = {
              DEFAULT_BRANCH = "master";
            };
            lfs = {
              # LFSオブジェクトのストレージにgarage(S3互換)を使用。
              STORAGE_TYPE = "minio";
              MINIO_ENDPOINT = "[${garageAddr}]:3900";
              MINIO_BUCKET = "forgejo";
              MINIO_LOCATION = "garage";
              # 内部のIP直アクセスのためSSLは不要。
              MINIO_USE_SSL = false;
              # コンテナ間はIP直アクセスのためpath style。
              MINIO_BUCKET_LOOKUP = "path";
            };
          };
          # S3キーはgarage-setupが起動ごとに生成するため、
          # LoadCredential経由でファイルから読み込みます。
          secrets.lfs = {
            MINIO_ACCESS_KEY_ID = "/run/garage-setup/forgejo/s3-access-key";
            MINIO_SECRET_ACCESS_KEY = "/run/garage-setup/forgejo/s3-secret-key";
          };
        };
        # コンテナ内で管理CLIコマンドを使えるようにします。
        environment.systemPackages = [ config.services.forgejo.package ];
      };
  };

  # forgejoの出口。
  # LFSオブジェクトは上の`settings.lfs`の通りgarageのS3 APIへ置く。
  # ミラーの取得やwebhookの送信や外部アバターの取得にはインターネットが要る。
  # PostgreSQLはUnixソケットで、外からの到達はCloudflare TunnelとホストのDNATなので、
  # それ以外の経路は要らない。
  local.machineEgress.forgejo = {
    internet = true;
    destinations = [
      {
        address = garageAddr;
        tcpPorts = [ 3900 ];
      }
    ];
  };

  # コンテナ外部から使える管理CLIコマンド。
  environment.systemPackages = [ forgejoWrapper ];
}
