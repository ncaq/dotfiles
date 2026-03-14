{
  pkgs,
  lib,
  config,
  hostName,
  username,
  ...
}:
let
  userConfig = config.users.users.${username};
in
lib.mkIf (hostName != "seminar") {
  # seminarサーバーのchihiro共有を自動マウントするための設定。
  # ネットワーク、Tailscale、sopsシークレットが揃った時点でマウントを試行する。
  systemd = {
    # `fileSystems`ではなく`systemd.mounts`を使用する理由:
    # NixOSの`fileSystems`はfstabエントリのみ生成し、
    # systemd mountユニットはsystemd-fstab-generatorが実行時に動的生成する。
    # しかし`switch-to-configuration`は静的ユニットファイルを直接開こうとするため、
    # ライブスイッチ時に"Failed to open unit file"エラーが発生する(nixpkgs#398523)。
    # `systemd.mounts`を使えば静的ユニットファイルが生成され、この問題を回避できる。
    mounts = [
      {
        requires = [ "network-online.target" ];
        wants = [
          "sops-install-secrets.service"
          "tailscale-online.service"
        ];
        after = [
          "network-online.target"
          "sops-install-secrets.service"
          "tailscale-online.service"
        ];
        what = "//seminar/chihiro";
        where = "/mnt/chihiro";
        type = "cifs";
        options = lib.concatStringsSep "," [
          # 認証
          "credentials=${config.sops.templates."cifs-credentials".path}"
          "uid=${toString userConfig.uid}"
          "gid=${toString config.users.groups.${userConfig.group}.gid}"
          # セキュリティ
          "nodev"
          "noexec"
          "nosuid"
          # パフォーマンス
          "noatime"
        ];
        mountConfig = {
          TimeoutSec = 30;
        };
        # remote-fs.targetはmulti-user.targetのクリティカルチェーン上にあるため、
        # ここにwantedByすると、Tailscale接続待ち+CIFSマウントがブート時間に加算される。
        # multi-user.targetへのWantsにすることでブートと並行して非同期にマウントを試行する。
        wantedBy = [ "multi-user.target" ];
      }
    ];

    # Tailscale接続確立を待つサービス。
    # tailscaled.serviceが起動してからtailnet接続が確立されるまでの遅延を吸収する。
    services.tailscale-online = {
      description = "Wait for Tailscale to be online";
      requires = [ "tailscaled.service" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "tailscaled.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "wait-for-tailscale";
            runtimeInputs = [ config.services.tailscale.package ];
            text = ''
              until tailscale status --peers=false > /dev/null 2>&1; do
                sleep 1
              done
            '';
          }
        );
        TimeoutStartSec = 60;
      };
    };

    tmpfiles.rules = [
      "d /mnt/chihiro 0000 root root -"
    ];
  };

  environment.systemPackages = with pkgs; [ cifs-utils ];

  sops = {
    templates."cifs-credentials" = {
      # サーバ側が固定でユーザ名`ncaq`を期待しているのでハードコーディングしています。
      content = ''
        username=ncaq
        password=${config.sops.placeholder."cifs-password"}
      '';
      mode = "0400";
    };
    secrets."cifs-password" = {
      sopsFile = ../../secrets/samba.yaml;
      key = "password";
      mode = "0400";
    };
  };
}
