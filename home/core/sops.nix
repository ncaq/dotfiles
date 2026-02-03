{
  config,
  ...
}:
{
  # home-manager用sops-nixの設定
  sops.gnupg.home = "${config.home.homeDirectory}/.gnupg";
}
