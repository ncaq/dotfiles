{
  pkgs,
  lib,
  config,
  hardening,
  ...
}:
let
  addr = config.machineAddresses.cdn;
  # コンテナの中のCaddyが待ち受けるポート。
  cdnPort = 8080;
  inherit (config.local.cdnDeploy)
    cdnRoot
    deployRoot
    deployStamp
    syncUser
    syncService
    origin
    ;
  # ジョブが書き込む配信コンテンツ。
  deployPublic = "${deployRoot}/public";
  # ステージングから配信ディレクトリへ写すスクリプト。
  #
  # `public`がシンボリックリンクだったら写さずに失敗させます。
  # 同期は隔離された場所で動くので、
  # リンクの先にあるのはホストのファイルではなく空のディレクトリだったりします。
  # そのまま写すと`--delete`で配信ディレクトリが空になるので、写す前に止めます。
  #
  # 同期の途中で次のジョブが`deployed`を更新しても、
  # path unitからの起動は今動いている起動にまとめられて、もう一度は走りません。
  # 写し始める前の`deployed`の時刻を覚えておいて、
  # 写し終えた時に更新されていたら写し直します。
  syncScript = pkgs.writeShellApplication {
    name = "cdn-ncaq-net-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.rsync
    ];
    text = ''
      seen=$(mktemp)
      while true; do
        touch --reference=${deployStamp} "$seen"
        if [[ -L ${deployPublic} || ! -d ${deployPublic} ]]; then
          echo "${deployPublic} is not a real directory" >&2
          exit 1
        fi
        rsync \
          --recursive \
          --times \
          --perms \
          --chmod=D755,F644 \
          --delete \
          --delete-after \
          --delay-updates \
          --no-links \
          --no-devices \
          --no-specials \
          -- ${deployPublic}/ ${cdnRoot}/
        if [[ ! ${deployStamp} -nt "$seen" ]]; then
          break
        fi
        echo "${deployStamp} was updated during sync, syncing again"
      done
    '';
  };
in
{
  # ランナーのVMの共有の定義と`test/nixos-boot`のブートテストが、
  # ここからパスや名前を参照します。
  options.local.cdnDeploy = lib.mkOption {
    type = lib.types.submodule {
      options = {
        cdnRoot = lib.mkOption {
          type = lib.types.str;
          description = "Caddyが配信するディレクトリ。ホストとコンテナで同じパス。";
        };
        origin = lib.mkOption {
          type = lib.types.str;
          description = "Cloudflare Tunnelが転送する先の、コンテナの中のCaddyのURL。";
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
      # 印は`public`の外に置きます。
      # `public`の中に置くと、ジョブのrsyncの`--delete`が書き込みの途中で印を消します。
      # 消えたこともpath unitには変化に見えるので、
      # その時点の書き込みの途中の状態を写してしまいます。
      deployStamp = "${deployRoot}/deployed";
      syncUser = "cdn-ncaq-net";
      syncService = "cdn-ncaq-net-sync";
      origin = "http://${addr.guest}:${toString cdnPort}";
    };
    description = "cdn.ncaq.netのデプロイの受け渡しと配信の定義。";
  };

  config = {
    # cdn.ncaq.netの静的ファイル配信。
    # 以前はCloudflare Pagesで配信していましたが、
    # Pagesには1ファイル25MiBの制限があり配信できないファイルがあるため、
    # seminarからCloudflare Tunnel経由で配信します。
    # TLS終端はCloudflare側で行われるためオリジンはHTTPのみで済みます。
    services.cloudflared.tunnels.seminar.ingress."cdn.ncaq.net" = origin;

    # 配信するCaddyはホストのCaddyとは分けてコンテナで動かします。
    # インターネットから直接リクエストを受けるのに、
    # 中身はcdn.ncaq.netのリポジトリへpushできる誰かが決めるので、
    # 同期でシンボリックリンクを捨てている(下の`services.${syncService}`)のに加えて、
    # Caddy自体の脆弱性やリンクの扱いの漏れがあっても、
    # 届くのが配信ディレクトリとストアだけになるようにします。
    # 動的なプログラムを動かすわけではないので、microVMではなくコンテナにしています。
    containers.cdn = {
      autoStart = true;
      ephemeral = true;
      privateNetwork = true;
      # 毎起動ランダムな高位UID範囲へマップして、
      # コンテナを脱出されてもホスト上では無権限のUIDになるようにします。
      privateUsers = "pick";
      hostAddress = addr.host;
      localAddress = addr.guest;
      hostAddress6 = addr.host6;
      localAddress6 = addr.guest6;
      # 配信ディレクトリは同期で`D755,F644`に揃えているので、
      # UIDがマップされないpickでもotherのパーミッションで読めます。
      # 書く必要は無いのでidmapは付けずに読み取り専用で渡します。
      bindMounts.${cdnRoot} = {
        hostPath = cdnRoot;
        isReadOnly = true;
      };
      config = {
        system.stateVersion = "26.05";
        networking.firewall.allowedTCPPorts = [ cdnPort ];
        services.caddy = {
          enable = true;
          # admin APIは使わないので切ります。
          # 切るとreloadができないので、設定の変更は再起動で反映させます。
          globalConfig = ''
            admin off
          '';
          enableReload = false;
          # ホスト名なしのポート指定にすることでCaddyの自動HTTPSを無効にしています。
          virtualHosts.":${toString cdnPort}" = {
            # 既定のアクセスログの出力先の`/var/log/caddy`は、
            # ephemeralなコンテナでは再起動のたびに消えます。
            # journalへ流せばホストのjournalに残り、`machine-log cdn`で読めます。
            logFormat = ''
              output stderr
            '';
            extraConfig = ''
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
        };
        # 1024以上のポートで平文のHTTPを返すだけなので、
        # パッケージのユニットが渡す`CAP_NET_BIND_SERVICE`と`CAP_NET_ADMIN`も外します。
        # `CAP_NET_ADMIN`はHTTP/3のUDPバッファを広げるためのもので、HTTPSを持たないので使いません。
        systemd.services.caddy.serviceConfig = hardening.network // {
          AmbientCapabilities = "";
        };
      };
    };

    # 配信はリクエストへ応答するだけで、
    # リダイレクトも応答として返すだけなので、外へ出る理由がありません。
    local.machineEgress.cdn = { };

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
        #
        # ステージング自体はrootの所有にして、
        # ジョブが`public`をシンボリックリンクへ差し替えられないようにします。
        # 同期は`public/`を転送元にするので、
        # 差し替えられると`--no-links`の効かない転送元のパスでリンクが辿られます。
        # ジョブが書けるのは`public`の中と`deployed`だけです。
        "d ${deployRoot} 0755 root root -"
        "d ${deployPublic} 0755 github-runner github-runner -"
        "f ${deployStamp} 0644 github-runner github-runner -"
        # 配信ディレクトリ。
        # 同期のサービスだけが書き込み、コンテナの中のCaddyはother権限で読み取ります。
        "d ${cdnRoot} 0755 ${syncUser} ${syncUser} -"
      ];

      # ステージングから配信ディレクトリへ写します。
      #
      # Caddyの`file_server`はシンボリックリンクを辿り、辿らない設定もありません。
      # ランナーのジョブが配信ディレクトリへ直接書けると、
      # `/etc`などを指すリンクを置くだけで、
      # Caddyが読めるファイルを公開できてしまいます。
      # Caddyはコンテナの中で動くのでホストのファイルには届きませんが、
      # コンテナの中の設定やストアのパスも配信する理由は無いので、ここで捨てます。
      # ジョブのrsyncのオプションはジョブ自身が書き換えられるので境界になりません。
      # ジョブにはステージングだけを書かせて、
      # 写す時にホストの側でシンボリックリンクとデバイスと特殊ファイルを捨てます。
      #
      # `--archive`はリンクや所有者を持ち込むので使わず、必要なものだけを指定します。
      # 比べるのは既定のサイズとmtimeで、中身は読みません。
      # checkoutのたびにmtimeは変わりますが、
      # cdn.ncaq.netのワークフローは`--checksum`付きで`--times`無しのrsyncでステージングへ書くので、
      # 中身が変わらないファイルはステージングでmtimeが保たれます。
      services.${syncService} = {
        description = "Sync cdn.ncaq.net content from runner staging";
        serviceConfig = hardening.isolated // {
          Type = "oneshot";
          User = syncUser;
          Group = syncUser;
          ExecStart = lib.getExe syncScript;
          BindReadOnlyPaths = [ deployRoot ];
          BindPaths = [ cdnRoot ];
          ReadWritePaths = [ cdnRoot ];
        };
        # 同期の途中にジョブがファイルをリンクへ差し替えた時や、
        # 何かの理由で`public`自体がリンクになった時に、
        # 辿った先にホストのファイルが無いようにします。
        # ルートはExecStartの閉包のストアのパスだけを置いたtmpfsになり、
        # 他に見えるのはステージングと配信ディレクトリだけです。
        # `/etc`や`/run`や他のストアのパスはそもそも存在しません。
        # 閉包に入るrsyncなどのパッケージは誰でも読める公開のものです。
        confinement.enable = true;
      };
      paths.${syncService} = {
        wantedBy = [ "paths.target" ];
        pathConfig.PathChanged = deployStamp;
      };
    };
  };
}
