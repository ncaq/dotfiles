{
  config,
  pkgs,
  ...
}:
let
  addr = config.machineAddresses.atticd;
  user = config.containerUsers.atticd;
  # ファイルシステムとPostgreSQLの認証で必要なためホストとゲストで設定が共通している必要があります。
  atticdUser = {
    inherit (user) uid;
    group = "atticd";
    isSystemUser = true;
  };
  # ホストからコンテナ内のatticd-atticadmコマンドを実行するラッパースクリプト
  atticadmWrapper = pkgs.writeShellScriptBin "atticd-atticadm" ''
    exec nixos-container run atticd -- atticd-atticadm "$@"
  '';
in
{
  containers.atticd = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;
    hostAddress = addr.host;
    localAddress = addr.guest;
    bindMounts = {
      "/etc/atticd.env" = {
        hostPath = config.sops.secrets."atticd-env".path;
        isReadOnly = true;
      };
      "/run/postgresql" = {
        hostPath = "/run/postgresql";
        isReadOnly = true;
      };
      "/mnt/noa/atticd" = {
        hostPath = "/mnt/noa/atticd";
        isReadOnly = false;
      };
    };
    config =
      { lib, ... }:
      {
        system.stateVersion = "25.05";
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        networking.firewall.trustedInterfaces = [ "eth0" ];
        users.users.atticd = atticdUser;
        users.groups.atticd.gid = user.gid;
        services.atticd = {
          enable = true;
          environmentFile = "/etc/atticd.env";
          settings = {
            listen = "[::]:8080";
            allowed-hosts = [ "seminar.border-saurolophus.ts.net" ];
            # 他のホストを指定してもプログラムが自動で設定し直してしまうことがあるため、
            # tailnet内部からでも外部からでもアクセス可能なエンドポイントを指定。
            api-endpoint = "https://seminar.border-saurolophus.ts.net/nix/cache/";
            database.url = "postgresql:///atticd?host=/run/postgresql";
            storage = {
              type = "local";
              path = "/mnt/noa/atticd";
            };
            garbage-collection = {
              interval = "1 day";
              default-retention-period = "6 months";
            };
          };
        };
      };
  };

  users.users.atticd = atticdUser;
  users.groups.atticd.gid = user.gid;

  systemd.tmpfiles.rules = [
    "d /mnt/noa/atticd 0755 atticd atticd -"
  ];

  # Wait for PostgreSQL to be ready before starting container.
  systemd.services."container@atticd" = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
  };

  # コンテナ外部から使える管理CLIコマンド。
  environment.systemPackages = [ atticadmWrapper ];

  # ```
  # openssl genrsa -traditional 4096 | base64 -w0
  # ```
  # で生成した鍵を`ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64`に指定。
  sops.secrets."atticd-env" = {
    sopsFile = ../../../secrets/seminar/atticd.yaml;
    key = "attic_env";
    owner = "atticd";
    group = "atticd";
    mode = "0400";
  };

  # 基本的には自動化されているので手動でトークンを発行する必要はないですが、
  # 一応参考までに手順を記載しておきます。
  # Token generation examples:
  # ```
  # sudo atticd-atticadm make-token --sub 'seminar' --validity '4y' --pull 'private' --push 'private' --create-cache 'private'
  # ```
  # Read/write token example:
  # ```
  # sudo atticd-atticadm make-token --sub 'client' --validity '4y' --pull 'private' --push 'private'
  # ```
  # Login with token:
  # ```
  # attic login ncaq https://seminar.border-saurolophus.ts.net/nix/cache/ "$TOKEN"
  # ```
}
