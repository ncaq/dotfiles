{
  config,
  hardening,
  ...
}:
let
  addr = config.machineAddresses.cdn;
  # コンテナの中のCaddyが待ち受けるポート。
  cdnPort = 8080;
  inherit (config.services.cdn-ncaq-net-sync) cdnRoot;
  # Cloudflare Tunnelが転送する先の、コンテナの中のCaddyのURL。
  origin = "http://[${addr.guest6}]:${toString cdnPort}";
in
{
  imports = [ ../../../pkgs/cdn-ncaq-net-sync/module.nix ];

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
    # 同期でシンボリックリンクを捨てている(下の`services.cdn-ncaq-net-sync`)のに加えて、
    # Caddy自体の脆弱性やリンクの扱いの漏れがあっても、
    # 届くのが配信ディレクトリとストアだけになるようにします。
    # 動的なプログラムを動かすわけではないので、microVMではなくコンテナにしています。
    containers.cdn = {
      # 配信ディレクトリは同期で`D755,F644`に揃えているので、
      # UIDがマップされない`privateUsers = "pick"`でもotherのパーミッションで読めます。
      # 書く必要は無いのでidmapは付けずに読み取り専用で渡します。
      bindMounts.${cdnRoot} = {
        hostPath = cdnRoot;
        isReadOnly = true;
      };
      config = {
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

    # ステージングから配信ディレクトリへ写す同期。
    # ユニットとディレクトリの定義は、コマンドの隣(`pkgs/cdn-ncaq-net-sync/module.nix`)にあります。
    services.cdn-ncaq-net-sync = {
      enable = true;
      # 速度をあまり求めないデータの集積場なので/mnt/noa以下に置きます。
      # `/mnt/noa`は`nofail`なので、マウントに失敗してもブートは進みます。
      # その時に同期が動かないことは、モジュールの側で保証しています。
      cdnRoot = "/mnt/noa/cdn.ncaq.net";
      # cdn.ncaq.netのランナのVMへvirtiofsで共有するステージングです。
      # VMの起動前に存在している必要があります。
      deployRoot = "/mnt/noa/cdn.ncaq.net-deploy";
      # 共有を通してVMの誰が書いても、ホストでは`github-runner`の所有になります。
      stagingUser = "github-runner";
    };
  };
}
