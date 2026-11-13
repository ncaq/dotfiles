{
  pkgs,
  lib,
  config,
  hardening,
  ...
}:
let
  # cloudflaredからCaddyへ内部ルーティングするためのポート。
  # 以前は8081をTailscale Serve用の中継に使っていたため、それを避けて8082にした名残。
  cdnPort = 8082;
  inherit (config.local.cdnDeploy)
    cdnRoot
    deployRoot
    deployStamp
    syncUser
    syncService
    ;
  # ジョブが書き込む配信コンテンツ。
  deployPublic = "${deployRoot}/public";
in
{
  # ランナーのVMの共有の定義と`lib/test-nixos-boot.nix`のブートテストが、
  # ここからパスや名前を参照します。
  options.local.cdnDeploy = lib.mkOption {
    type = lib.types.submodule {
      options = {
        cdnRoot = lib.mkOption {
          type = lib.types.str;
          description = "Caddyが配信するディレクトリ。";
        };
        deployRoot = lib.mkOption {
          type = lib.types.str;
          description = "cdn.ncaq.netのランナーのVMへ共有するステージングのディレクトリ。";
        };
        deployStamp = lib.mkOption {
          type = lib.types.str;
          description = "ジョブが配信コンテンツを書き終えた印のファイル。";
        };
        syncUser = lib.mkOption {
          type = lib.types.str;
          description = "配信ディレクトリを所有して同期を行うホスト専用のユーザ。";
        };
        syncService = lib.mkOption {
          type = lib.types.str;
          description = "ステージングから配信ディレクトリへ写すサービスの名前。";
        };
      };
    };
    readOnly = true;
    default = rec {
      # 速度をあまり求めないデータの集積場なので/mnt/noa以下に置きます。
      cdnRoot = "/mnt/noa/cdn.ncaq.net";
      deployRoot = "/mnt/noa/cdn.ncaq.net-deploy";
      # `public`の外に置くのは、
      # ジョブのrsyncの`--delete`で印が消えた時の通知で、
      # 書き込みの途中の状態を写さないためです。
      deployStamp = "${deployRoot}/deployed";
      syncUser = "cdn-ncaq-net";
      syncService = "cdn-ncaq-net-sync";
    };
    description = "cdn.ncaq.netのデプロイの受け渡しの定義。";
  };

  config = {
    services = {
      # cdn.ncaq.netの静的ファイル配信。
      # 以前はCloudflare Pagesで配信していましたが、
      # Pagesには1ファイル25MiBの制限があり配信できないファイルがあるため、
      # seminarからCloudflare Tunnel経由で配信します。
      # TLS終端はCloudflare側で行われるためオリジンはHTTPのみで済みます。
      cloudflared.tunnels.seminar.ingress."cdn.ncaq.net" = "http://127.0.0.1:${toString cdnPort}";

      # コンテンツはホストの同期のサービスが配信ディレクトリへ置きます。
      caddy.virtualHosts.":${toString cdnPort}".extraConfig = ''
        bind 127.0.0.1
        # 過去に持っていたコンテンツのリダイレクト定義。
        redir /dic-nico-intersection-pixiv.txt https://raw.githubusercontent.com/ncaq/dic-nico-intersection-pixiv/master/public/dic-nico-intersection-pixiv-google.txt permanent
        redir /keymap.txt https://raw.githubusercontent.com/ncaq/dotfiles/master/mozc/keymap.txt permanent
        redir /nlod.txt https://raw.githubusercontent.com/ncaq/dotfiles/master/mozc/nlod.txt temporary
        redir /uBlacklist.txt https://raw.githubusercontent.com/ncaq/uBlacklistRule/master/uBlacklist.txt permanent
        redir /uBlockOrigin.txt https://raw.githubusercontent.com/ncaq/uBlacklistRule/master/uBlockOrigin.txt permanent
        # ファイルをそのまま配信。
        root * ${cdnRoot}
        # browseによりディレクトリアクセス時はファイル一覧ページを表示します。
        file_server browse
      '';
    };

    users = {
      users.${syncUser} = {
        isSystemUser = true;
        group = syncUser;
      };
      groups.${syncUser} = { };
    };

    systemd = {
      tmpfiles.rules = [
        # ステージングのディレクトリ。
        # cdn.ncaq.netのGitHub Actionsのセルフホストランナーが、
        # `public`へrsyncで書き込んでから`deployed`をtouchします。
        # ランナーのVMへvirtiofsで共有するディレクトリなので、
        # VMの起動前に存在している必要があります。
        # 共有を通してVMの誰が書いても、ホストでは`github-runner`の所有になります。
        "d ${deployRoot} 0755 github-runner github-runner -"
        # 配信ディレクトリ。
        # 同期のサービスだけが書き込み、Caddyはother権限で読み取ります。
        "d ${cdnRoot} 0755 ${syncUser} ${syncUser} -"
        # 以前はランナーが直接書き込んでいたので、
        # その頃の`github-runner`の所有のファイルを同期のユーザへ移します。
        "Z ${cdnRoot} - ${syncUser} ${syncUser} -"
      ];

      # ステージングから配信ディレクトリへ写します。
      #
      # Caddyの`file_server`はシンボリックリンクを辿り、辿らない設定もありません。
      # ランナーのジョブが配信ディレクトリへ直接書けると、
      # `/etc`や`/var/lib/caddy`を指すリンクを置くだけで、
      # Caddyが読めるホストのファイルを公開できてしまいます。
      # ジョブのrsyncのオプションはジョブ自身が書き換えられるので境界になりません。
      # ジョブにはステージングだけを書かせて、
      # 写す時にホストの側でシンボリックリンクとデバイスと特殊ファイルを捨てます。
      #
      # `--archive`はリンクや所有者を持ち込むので使わず、必要なものだけを指定します。
      # checkoutのたびにmtimeが変わるので、中身で比べます。
      services.${syncService} = {
        description = "Sync cdn.ncaq.net content from runner staging";
        serviceConfig = hardening.isolated // {
          Type = "oneshot";
          User = syncUser;
          Group = syncUser;
          ExecStart = lib.escapeShellArgs [
            (lib.getExe pkgs.rsync)
            "--recursive"
            "--times"
            "--perms"
            "--chmod=D755,F644"
            "--checksum"
            "--delete"
            "--delete-after"
            "--delay-updates"
            "--no-links"
            "--no-devices"
            "--no-specials"
            "--"
            "${deployPublic}/"
            "${cdnRoot}/"
          ];
          # 同期の途中にジョブがファイルをリンクへ差し替えても、
          # 辿った先に読めるものが無いように、
          # ステージングと配信ディレクトリ以外の`/mnt`と`/var`を隠します。
          TemporaryFileSystem = [
            "/mnt"
            "/var"
          ];
          BindReadOnlyPaths = [ deployRoot ];
          BindPaths = [ cdnRoot ];
          ReadWritePaths = [ cdnRoot ];
        };
      };
      paths.${syncService} = {
        wantedBy = [ "paths.target" ];
        pathConfig.PathChanged = deployStamp;
      };
    };
  };
}
