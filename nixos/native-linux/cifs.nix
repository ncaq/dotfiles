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
lib.mkMerge [
  (lib.mkIf (hostName != "seminar") {
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
          # `cifs-mount.target`に向けてwantedByする。
          # systemdはマウントユニットのwantedBy先に暗黙的に`Before=`を追加するが、
          # `cifs-mount.target`自体は`multi-user.target`に対して`Before=`を持たないため、
          # ブートをブロックしない。
          wantedBy = [ "cifs-mount.target" ];
          what = "//seminar/chihiro";
          where = "/mnt/chihiro";
          type = "cifs";
          options = lib.concatStringsSep "," [
            # 認証
            "credentials=${config.sops.templates."cifs-credentials".path}"
            "uid=${toString userConfig.uid}"
            "gid=${toString config.users.groups.${userConfig.group}.gid}"
            # systemdはデフォルトだと`Before=remote-fs.target`を追加します。
            # `nofail`を指定することでその挙動が抑制され、
            # `remote-fs.target`経由のブートブロックを防ぎます。
            "nofail"
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
        }
      ];

      # ターゲットユニットにはwantedBy先への暗黙的`Before=`が付かないため、
      # `multi-user.target`をブロックせずにマウントを引き込める。
      targets.cifs-mount = {
        description = "CIFS Network Mounts";
        wantedBy = [ "multi-user.target" ];
      };

      # Tailscale接続確立を待つサービス。
      # `tailscaled.service`が起動してからtailnet接続が確立されるまでの遅延を吸収する。
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
  })
  (lib.mkIf (hostName == "seminar") {
    # seminarサーバ側でも同じようにパスにアクセスできるようにシンボリックリンクを作成します。
    systemd.tmpfiles.rules = [
      "L+ /mnt/chihiro - - - - /mnt/noa/chihiro/"
    ];
  })
]
