{ pkgs, config, ... }:
{
  sops = {
    # sops-install-secrets.serviceを生成し、他のサービスから明示的に依存可能にする。
    useSystemdActivation = true;
    # gnupgの設定を明示的に指定します。
    # 秘密鍵はgpg-vaultユーザに隔離されているため(gpg-vault.nix)、
    # そちらのGNUPGHOMEを参照します。
    # 復号はvault agentにソケット経由で委譲されるため、
    # gpg-vault.nixの`clientUnits`に`sops-install-secrets.service`を入れています。
    # それを受けて`pkgs/gpg-vault/module.nix`が、agentをこのユニットより前に起動します。
    gnupg = {
      home = config.services.gpg-vault.gnupgHome;
      sshKeyPaths = [ ];
    };
  };

  environment.systemPackages = [ pkgs.sops ];

  # 個別のシークレットは使用する各モジュールで定義します。
  # 例:
  # sops.secrets."something/api-token" = {
  #   sopsFile = ../../../secrets/something.yaml;
  #   key = "api_token";
  # };
  # services.something.tokenFile = config.sops.secrets."something/api-token".path
}
