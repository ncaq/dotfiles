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
  mountUnitName = "mnt-chihiro.mount";
in
{
  # より細かく制御したいのでfileSystemsではなくsystemdのmount単位で制御。
  # wantedByは設定せず、別のサービスからトリガーする。
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
        # tailscale0デバイスが存在するのでtailnetに接続しているはず。
        "sys-devices-virtual-net-tailscale0.device"
      ];
      # sopsの認証情報ファイルが存在する場合のみマウントを試行
      unitConfig.ConditionPathExists = config.sops.templates."cifs-credentials".path;
      options = builtins.concatStringsSep "," [
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
      ];
    }
  ];

  # home-managerのactivation後にマウントをトリガーするサービス
  systemd.services.cifs-mount-trigger = {
    description = "Trigger CIFS mount after home-manager activation";
    requires = [
      "network-online.target"
      "tailscaled.service"
    ];
    after = [
      "network-online.target"
      "tailscaled.service"

      "home-manager-${username}.service"
      "sys-devices-virtual-net-tailscale0.device"
    ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = config.sops.templates."cifs-credentials".path;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl start ${mountUnitName}";
      RemainAfterExit = true;
    };
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
