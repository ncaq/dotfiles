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
  # mountユニットの依存関係を設定
  # fileSystems.${mountPoint}ではなくsystemd.mountsを使う理由:
  # - automountと組み合わせるとビルドが壊れることがある
  # - 依存関係をより細かく制御可能
  systemd.mounts = [
    {
      where = mountPoint;
      what = cifsServer;
      type = "cifs";
      requires = [
        "network-online.target"
        "tailscaled.service"
      ];
      after = [
        "network-online.target"
        "tailscaled.service"
      ];
      options = builtins.concatStringsSep "," [
        "credentials=${config.sops.templates."cifs-credentials".path}"
        "uid=${toString userConfig.uid}"
        "gid=${toString config.users.groups.${userConfig.group}.gid}"
        "_netdev"
        "nofail"
        "noexec"
        "nosuid"
        "noauto" # ユーザレベルのsopsを待つ必要があるため自動マウントはしません。
        "noatime"
      ];
    }
  ];

  # x-systemd.automountの代わりにsystemd.automountsを使用
  # fstabのx-systemd.automountはsystemd-fstab-generatorで生成されるため、
  # NixOSのswitch-to-configurationが正しく処理できない問題がある
  systemd.automounts = [
    {
      where = mountPoint;
      wantedBy = [ "multi-user.target" ];
    }
  ];

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
