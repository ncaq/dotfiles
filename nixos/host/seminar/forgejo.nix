{ config, ... }:
{
  services.forgejo = {
    enable = true;
    database = {
      type = "postgres";
    };
    settings = {
      server = {
        HTTP_PORT = 10001;
        DOMAIN = "forgejo.ncaq.net";
        ROOT_URL = "https://forgejo.ncaq.net/"; # デフォルトだとCloudflareを介した外から見たportにならないので手動で指定します。
        SSH_DOMAIN = "forgejo-ssh.ncaq.net"; # Cloudflare Tunnelは複数のプロトコルを同一ドメインで扱えないため分けます。
      };
      session = {
        COOKIE_SECURE = true;
      };
      service = {
        # 個人専用向けにふさわしい設定。
        DISABLE_REGISTRATION = true; # 新規登録を無効化。
        REQUIRE_SIGNIN_VIEW = true; # サイト閲覧にログインを必須化。
      };
      repository = {
        DEFAULT_BRANCH = "master";
      };
    };
  };
  environment.systemPackages = [
    config.services.forgejo.package # サーバ上で管理CLIコマンドを使えるようにします。
  ];
}
