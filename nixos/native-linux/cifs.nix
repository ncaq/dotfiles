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
  # seminarのSMBポートへ実際にTCP接続できるまで待つスクリプト。
  # `network-online.target`や`tailscale-online.service`はどちらも
  # 「seminarに到達できる」ことまでは保証しないため、
  # マウント前に実到達性を確認する必要がある。
  waitForSeminar = pkgs.writeShellApplication {
    name = "wait-for-seminar";
    runtimeInputs = with pkgs; [
      bash
      coreutils
    ];
    text = ''
      until timeout 5 bash -c ': < /dev/tcp/seminar/445'; do
        sleep 2
      done
    '';
  };
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
            "seminar-online.service"
            "sops-install-secrets.service"
            "tailscale-online.service"
          ];
          after = [
            "network-online.target"
            "seminar-online.service"
            "sops-install-secrets.service"
            "tailscale-online.service"
          ];
          unitConfig = {
            # マウント失敗時はリトライ用サービスに委ねる。
            # mountユニット自体はRestart=を持てないため、
            # 到達性を待ってから再マウントする別サービスで補う。
            OnFailure = [ "mnt-chihiro-retry.service" ];
            # リトライが恒久的な失敗(認証エラーなど)で無限ループしないよう起動回数を制限する。
            StartLimitIntervalSec = 600;
            StartLimitBurst = 5;
          };
          # `cifs-mount.target`に向けてwantedByする。
          # `cifs-mount.target`は`DefaultDependencies=false`のため、
          # `multi-user.target`からの暗黙的な順序依存が追加されず、ブートをブロックしない。
          wantedBy = [ "cifs-mount.target" ];
          what = "//seminar/chihiro";
          where = "/mnt/chihiro";
          type = "cifs";
          options = lib.concatStringsSep "," [
            # 認証
            "credentials=${config.sops.templates."cifs-credentials".path}"
            "uid=${toString userConfig.uid}"
            "gid=${toString config.users.groups.${userConfig.group}.gid}"
            # 所有グループ(users)にも書き込みを許可する。
            # bulletのComfyUIコンテナなど、
            # uidの異なるサービスユーザがグループ経由で書き込めるようにするため。
            # デフォルトの0755ではファイルが実行可能に見えてしまう問題も直る。
            "dir_mode=0775"
            "file_mode=0664"
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
            # SMBダイアレクトを明示的に指定。
            # 未指定だとkernelが`No dialect specified on mount`の警告を出す。
            # `vers=3`はSMB3.0以上を意味し、ネゴシエーションで3.x系の最新版が選択される。
            # SMB1/SMB2系を排除しつつ、将来のマイナーバージョン更新にも自動追従する。
            "vers=3"
          ];
          mountConfig = {
            TimeoutSec = 30;
          };
        }
      ];

      services = {
        # seminarのSMBポートへの実到達性を確認するサービス。
        # `tailscale-online.service`はtailnetへの接続までしか保証せず、
        # seminar自体が起動していて到達可能かは別問題のため独立したサービスにしている。
        seminar-online = {
          description = "Wait for seminar SMB port to be reachable";
          wants = [
            "network-online.target"
            "tailscale-online.service"
          ];
          after = [
            "network-online.target"
            "tailscale-online.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # seminarがダウンしている場合に永久に待たないよう上限を設ける。
            # 失敗してもマウント側はwantsなので試行自体は行われ、nofailで害はない。
            TimeoutStartSec = 300;
            ExecStart = lib.getExe waitForSeminar;
          };
        };

        # マウント失敗時にOnFailureから起動されるリトライサービス。
        # 到達性が回復するまで待ってから再マウントする。
        mnt-chihiro-retry = {
          description = "Retry mounting /mnt/chihiro after failure";
          unitConfig = {
            # mount側のStartLimitだけに停止保証を頼らない。
            # mountがstart-limit-hitで拒否された場合にOnFailureが再発火するかは、
            # systemdのバージョンで挙動が異なるため(systemd/systemd#33710)、
            # 再発火する環境でもこのサービス自身の起動制限でループを確実に打ち切る。
            StartLimitIntervalSec = 600;
            StartLimitBurst = 5;
          };
          serviceConfig = {
            Type = "oneshot";
            TimeoutStartSec = 600;
            ExecStart = lib.getExe (
              pkgs.writeShellApplication {
                name = "retry-mnt-chihiro";
                runtimeInputs = with pkgs; [
                  coreutils
                  systemd
                  waitForSeminar
                ];
                # 失敗直後の即時再試行は同じ理由で失敗しやすいので少し置く。
                text = ''
                  sleep 10
                  wait-for-seminar
                  systemctl restart mnt-chihiro.mount
                '';
              }
            );
          };
        };
      };

      targets.cifs-mount = {
        description = "CIFS Network Mounts";
        wantedBy = [ "multi-user.target" ];
        # systemd.target(5)により、
        # ターゲットが`Wants=`で引き込んだユニットの両方が`DefaultDependencies=yes`の場合、
        # 暗黙的に`After=`が追加される。
        # `DefaultDependencies=false`を設定することで、
        # `multi-user.target`が暗黙的に`After=cifs-mount.target`を追加するのを防ぎ、
        # ブートをブロックしない。
        unitConfig.DefaultDependencies = false;
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
