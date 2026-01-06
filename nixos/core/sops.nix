{
  pkgs,
  username,
  ...
}:
{
  # sops-nix: NixOS用のシークレット管理。

  sops.gnupg = {
    home = "/home/${username}/.gnupg";
    sshKeyPaths = [ ];
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
