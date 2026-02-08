# CIFSによるseminarサーバーのchihiro共有フォルダのマウント設定
{
  pkgs,
  config,
  username,
  ...
}:
let
  userConfig = config.users.users.${username};
  mountPoint = "/mnt/chihiro";
  cifsServer = "//seminar/chihiro";
in
{
  fileSystems.${mountPoint} = {
    device = cifsServer;
    fsType = "cifs";
    options = [
      # 認証
      "credentials=${config.sops.templates."cifs-credentials".path}"
      # 所有者
      "uid=${toString userConfig.uid}"
      "gid=${toString config.users.groups.${userConfig.group}.gid}"
      # パフォーマンス
      "noatime"
      # 起動時自動ではマウントしません
      "noauto"
      # セキュリティ
      "noexec"
      "nosuid"
      # マウント失敗でもブート継続
      "nofail"
      # ネットワークファイルシステム(network-online.target後にマウント)
      "_netdev"
      # 依存関係
      "x-systemd.requires=sops-nix.service"
      "x-systemd.requires=tailscaled.service"
      "x-systemd.after=sops-nix.service"
      "x-systemd.after=tailscaled.service"
      # アクセス時にマウント
      "x-systemd.automount"
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
