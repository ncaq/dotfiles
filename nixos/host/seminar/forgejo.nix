{ config, ... }:
let
  addr = config.containerAddresses.forgejo;
in
{
  containers.forgejo = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = addr.host;
    localAddress = addr.container;
    bindMounts = {
      "/run/postgresql" = {
        hostPath = "/run/postgresql";
        isReadOnly = false;
      };
      "/var/lib/forgejo" = {
        hostPath = "/var/lib/forgejo";
        isReadOnly = false;
      };
    };
    config =
      { config, lib, ... }:
      {
        system.stateVersion = "25.05";
        networking.useHostResolvConf = lib.mkForce false;
        services.resolved.enable = true;
        services.forgejo = {
          enable = true;
          database = {
            type = "postgres";
          };
          settings = {
            server = {
              HTTP_PORT = 10001;
              DOMAIN = "forgejo.ncaq.net";
              ROOT_URL = "https://forgejo.ncaq.net/";
              SSH_DOMAIN = "forgejo-ssh.ncaq.net";
            };
            session = {
              COOKIE_SECURE = true;
            };
            service = {
              DISABLE_REGISTRATION = true;
              REQUIRE_SIGNIN_VIEW = true;
            };
            repository = {
              DEFAULT_BRANCH = "master";
            };
          };
        };
      };
  };
  # サーバで管理コマンドを実行できるようにします。
  environment.systemPackages = [ config.services.forgejo.package ];
}
