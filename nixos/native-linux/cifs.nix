# CIFSによるseminarサーバーのchihiro共有フォルダのマウント設定
# 自動マウントは行わず、手動で`sudo mount /mnt/chihiro`でマウントする。
{
  pkgs,
  config,
  username,
  ...
}:
let
  userConfig = config.users.users.${username};
in
{
  fileSystems."/mnt/chihiro" = {
    device = "//seminar/chihiro";
    fsType = "cifs";
    options = [
      # 認証
      "credentials=${config.sops.templates."cifs-credentials".path}"
      "uid=${toString userConfig.uid}"
      "gid=${toString config.users.groups.${userConfig.group}.gid}"
      # ネットワークドライブ向けオプション
      "_netdev"
      "noexec"
      "nofail"
      "nosuid"
      # 定番オプション
      "noatime"
      # ブート時に自動マウントしない
      "noauto"
    ];
  };

  sops.templates."cifs-credentials" = {
    content = ''
      username=ncaq
      password=${config.sops.placeholder."cifs-password"}
    '';
    mode = "0400";
  };
  sops.secrets."cifs-password" = {
    sopsFile = ../../secrets/samba.yaml;
    key = "password";
    mode = "0400";
  };

  environment.systemPackages = with pkgs; [ cifs-utils ];
}
