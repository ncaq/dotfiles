{
  config,
  ...
}:
{
  # GPGによる暗号化を行うpassを使用します。
  # あくまでメインのパスワードマネージャはKeePassXCです。
  # しかしdbusのAPIに対応したsecret serviceがあると便利なので併用します。
  # プレーンテキストよりはマシだと思います。
  # gnome-keyringではない理由はWSLとの連携が面倒だからです。
  # KeePassXCに繋げない理由はアンロックを意図的に面倒にしているので、
  # 常にアンロックしていることが期待できないからです。
  programs.password-store = {
    enable = true;
    settings = {
      # XDGデータディレクトリ以下にストアを置くため明示的に指定します。
      PASSWORD_STORE_DIR = "${config.xdg.dataHome}/password-store";
      # `pass init`による`.gpg-id`の生成の代わりに、
      # 暗号化先のGPG鍵を宣言的に指定します。
      # passは`PASSWORD_STORE_KEY`があれば`.gpg-id`より優先して使います。
      PASSWORD_STORE_KEY = "42248C7D0FB73D57";
    };
  };
  services.pass-secret-service.enable = true;
}
