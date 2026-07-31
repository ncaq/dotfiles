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
  inherit (import ../../lib/seminar-cifs.nix { inherit pkgs; })
    baseMountOptions
    mkRetryService
    waitForSeminar
    ;
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
          # 認証・セキュリティ・ダイアレクトの共通部分は`lib/seminar-cifs.nix`で管理する。
          options = lib.concatStringsSep "," (
            baseMountOptions config.sops.templates."cifs-credentials".path
            ++ [
              "uid=${toString userConfig.uid}"
              "gid=${toString config.users.groups.${userConfig.group}.gid}"
              # デフォルトの0755/0755だとファイルが実行可能に見えてしまうため、
              # ファイルから実行ビットを落とす。
              # 所有グループ(users)への書き込み許可も維持する。
              "dir_mode=0775"
              "file_mode=0664"
              # systemdはデフォルトだと`Before=remote-fs.target`を追加します。
              # `nofail`を指定することでその挙動が抑制され、
              # `remote-fs.target`経由のブートブロックを防ぎます。
              "nofail"
            ]
          );
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
        mnt-chihiro-retry = mkRetryService {
          name = "mnt-chihiro";
          description = "Retry mounting /mnt/chihiro after failure";
          mountUnit = "mnt-chihiro.mount";
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
