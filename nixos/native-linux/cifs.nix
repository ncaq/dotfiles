# CIFSによるseminarサーバーのchihiro共有フォルダのマウント設定
{
  pkgs,
  config,
  lib,
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

        "tailscale-seminar-online.service"
      ];
      # sopsの認証情報ファイルが存在する場合のみマウントを試行
      unitConfig.ConditionPathExists = config.sops.templates."cifs-credentials".path;
      # マウント/アンマウントのタイムアウトを短く設定(デフォルトは90秒)
      mountConfig.TimeoutSec = 10;
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
    wants = [
      "home-manager-${username}.service"
      "tailscale-seminar-online.service"
    ];
    after = [
      "home-manager-${username}.service"
      "tailscale-seminar-online.service"
    ];
    unitConfig.ConditionPathExists = config.sops.templates."cifs-credentials".path;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl start ${mountUnitName}";
      RemainAfterExit = true;
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Tailscaleが接続完了しMagicDNSでseminarが解決可能になるまで待つサービス
  systemd.services.tailscale-seminar-online = {
    description = "Wait for Tailscale seminar DNS resolution";
    requires = [ "tailscaled.service" ];
    after = [
      "tailscaled.service"
      "sys-devices-virtual-net-tailscale0.device"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # seminarのDNS解決ができるまで待機(最大30秒)
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "wait-for-tailscale-seminar";
          runtimeInputs = with pkgs; [
            coreutils
            dnsutils
          ];
          text = ''
            for _i in $(seq 1 30); do
              if nslookup seminar >/dev/null 2>&1; then
                exit 0
              fi
              sleep 1
            done
            echo "Timeout waiting for seminar DNS resolution" >&2
            exit 1
          '';
        }
      );
    };
    wantedBy = [ "multi-user.target" ];
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
