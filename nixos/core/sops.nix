{ pkgs, ... }:
{
  sops = {
    # sops-install-secrets.serviceを生成し、他のサービスから明示的に依存可能にする。
    useSystemdActivation = true;
    # gnupgの設定を明示的に指定します。
    # 秘密鍵はgpg-vaultユーザに隔離されているため(gpg-vault.nix)、
    # そちらのGNUPGHOMEを参照します。
    # sops-install-secretsはrootで動くので、
    # vault agentのソケット経由またはファイル直接読み取りで復号できます。
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
