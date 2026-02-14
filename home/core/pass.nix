{
  config,
  lib,
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
  programs.password-store.enable = true;
  services.pass-secret-service.enable = true;

  # `pass init`の代わりに宣言的にパスワードストアを初期化します。
  home.file."${lib.removePrefix "${config.home.homeDirectory}/" config.services.pass-secret-service.storePath}/.gpg-id".text =
    "42248C7D0FB73D57\n";
}
