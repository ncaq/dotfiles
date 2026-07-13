let
  # cloudflaredからCaddyへ内部ルーティングするためのポート。
  # 8081はTailscale Serve用(caddy.nix)に使っているので8082。
  cdnPort = 8082;
  # 配信コンテンツの置き場所。
  # 速度をあまり求めないデータの集積場なので/mnt/noa以下に置きます。
  cdnRoot = "/mnt/noa/cdn.ncaq.net";
in
{
  services = {
    # cdn.ncaq.netの静的ファイル配信。
    # 以前はCloudflare Pagesで配信していましたが、
    # Pagesには1ファイル25MiBの制限があり配信できないファイルがあるため、
    # seminarからCloudflare Tunnel経由で配信します。
    # TLS終端はCloudflare側で行われるためオリジンはHTTPのみで済みます。
    cloudflared.tunnels.seminar.ingress."cdn.ncaq.net" = "http://127.0.0.1:${toString cdnPort}";

    # コンテンツはcdn.ncaq.netリポジトリのGitHub Actionsが、
    # セルフホストランナー経由でrsyncしてきます。
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

  # 配信ディレクトリ。
  # GitHub Actionsセルフホストランナーがrsyncで書き込み、
  # Caddyはother権限で読み取ります。
  # github-runnerコンテナへのbindMountのhostPathとしても使われるため、
  # コンテナ起動前に存在している必要があります。
  systemd.tmpfiles.rules = [
    "d ${cdnRoot} 0755 github-runner github-runner -"
  ];
}
