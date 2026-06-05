{
  lib,
  config,
  ...
}:
let
  inherit (config.services.pass-secret-service) storePath;
  storeRel = lib.removePrefix "${config.home.homeDirectory}/" storePath;
in
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
      # 暗号化先のGPG鍵を宣言的に指定します。
      PASSWORD_STORE_KEY = "42248C7D0FB73D57";
    };
  };
  services.pass-secret-service.enable = true;

  # `pass init`の代わりに宣言的に`.gpg-id`を配置してストアを初期化します。
  # `pass-secret-service`が内部で使うプログラムは`PASSWORD_STORE_KEY`を読まず、
  # 起動時に`.gpg-id`の存在を必須とするため実ファイルの配置が避けられません。
  home.file."${storeRel}/.gpg-id".text =
    "${config.programs.password-store.settings.PASSWORD_STORE_KEY}\n";
}
