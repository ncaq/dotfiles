# sopsをモックにして必要とするサービスを誤魔化します。
{ lib, pkgs, ... }:
{
  sops = {
    validateSopsFiles = false;
    gnupg = {
      home = lib.mkForce "/run/sops-dummy";
      sshKeyPaths = lib.mkForce [ ];
    };
  };
  home-manager.sharedModules = lib.mkAfter [
    { sops.validateSopsFiles = false; }
  ];
  systemd.services.sops-install-secrets.serviceConfig = lib.mkForce {
    Type = "oneshot";
    ExecStart = "${pkgs.coreutils}/bin/true";
    RemainAfterExit = true;
  };
}
