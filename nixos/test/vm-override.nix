/**
  NixOS Testのマシンがブートするかを確認するときのVMの設定。
  テスト時には機能しないものなどを無効化したりモックにしたりします。
*/
{ pkgs, lib, ... }:
{
  # NixOS Testでいくらリソースを使っていいかの設定。
  # CIで実行する時はサーバのコンテナ単位でリソースを制限しているので、
  # 多めに設定していても破綻はしませんが、
  # リソース制限をわかりやすくするためにこちらでも記述しておきます。
  virtualisation = {
    cores = 6;
    memorySize = 4096;
    graphics = false;
  };

  # diskoのデバイス定義を無効化。
  # VMではvirtualisationモジュールがファイルシステムを管理します。
  disko.devices = lib.mkForce { };
  swapDevices = lib.mkForce [ ];

  # 仮想マシンの特殊なブートになるので普通のブート手順を無効化。
  boot = {
    loader = {
      efi.canTouchEfiVariables = lib.mkForce false;
      systemd-boot.enable = lib.mkForce false;
      grub.enable = lib.mkForce false;
    };
    initrd.luks.devices = lib.mkForce { };
  };

  # GPUドライバを無効化。
  services.xserver.videoDrivers = lib.mkForce [ ];

  # sopsをモックにして必要とするサービスを誤魔化します。
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
