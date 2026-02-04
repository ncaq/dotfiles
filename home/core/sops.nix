{
  username,
  ...
}:
{
  # home-manager用sops-nixの設定
  sops.gnupg.home = "/home/${username}/.gnupg";
}
