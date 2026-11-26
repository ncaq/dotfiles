{ username, ... }:
{
  # GPG秘密鍵を通常ユーザから隔離する仕組みの本体は、パッケージの隣にある。
  # GNUPGHOMEの設定とユニットの権限が対になっていて、パッケージのテストもそのユニットを動かすため。
  imports = [ ../../pkgs/gpg-vault/module.nix ];

  services.gpg-vault = {
    enable = true;
    inherit (import ../../key) fingerprint publicKeyFile sshKeygrip;
    users = [ username ];
    clientUnits = [
      # home-manager activationのimportGpgKeysなどはgpg-agentに接続します。
      "home-manager-${username}.service"
      # vaultのagent経由で復号します。
      "sops-install-secrets.service"
    ];
  };
}
