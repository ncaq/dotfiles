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
  systemd.services.sops-install-secrets.serviceConfig = lib.mkForce {
    Type = "oneshot";
    ExecStart = "${pkgs.coreutils}/bin/true";
    RemainAfterExit = true;
  };
}
