{ pkgs, ... }:
{
  sops = {
    # sops-install-secrets.serviceを生成し、他のサービスから明示的に依存可能にする。
    useSystemdActivation = true;
    # gnupgの設定を明示的に指定します。
    # 秘密鍵はgpg-vaultユーザに隔離されているため(gpg-vault.nix)、
    # そちらのGNUPGHOMEを参照します。
    # 復号はvault agentにソケット経由で委譲されるため、
    # gpg-vault.nix側で`gpg-vault-agent.service`への順序依存を設定しています。
    gnupg = {
      home = "/var/lib/gpg-vault/.gnupg";
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
  # services.something.tokenFile = config.sops.secrets."api-token".path
}
