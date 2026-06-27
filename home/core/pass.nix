{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (config.services.pass-secret-service) storePath;
  storeRel = lib.removePrefix "${config.home.homeDirectory}/" storePath;
  inherit (config.programs.password-store.settings) PASSWORD_STORE_KEY;
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

  # gitのcredential helperとしてpass-git-helperを使用します。
  # Forgejoの`https`エンドポイントへのアクセス時に、
  # passに格納されたトークンを返します。
  # 実際のhelperの紐付けは`programs.git.settings.credential`で行います。
  xdg.configFile."pass-git-helper/git-pass-mapping.ini".text = ''
    [forgejo.ncaq.net*]
    target=forgejo.ncaq.net/ncaq
    username=ncaq
  '';

  # sopsで管理されているForgejoのトークンを長期管理します。
  sops.secrets."forgejo/token/normal" = {
    sopsFile = ../../secrets/forgejo.yaml;
    key = "token/normal";
    mode = "0400";
  };

  home = {
    # `pass init`の代わりに宣言的に`.gpg-id`を配置してストアを初期化します。
    # `pass-secret-service`が内部で使うプログラムは`PASSWORD_STORE_KEY`を読まず、
    # 起動時に`.gpg-id`の存在を必須とするため実ファイルの配置が避けられません。
    file."${storeRel}/.gpg-id".text = "${PASSWORD_STORE_KEY}\n";

    # sopsで復号化したトークンをpassのエントリとして再暗号化して配置します。
    # 内容が変化した時のみ書き換えて`home-manager switch`の度に差分が出るのを避けます。
    activation.forgejoTokenToPass = lib.hm.dag.entryAfter [ "sops-nix" ] ''
      src="${config.sops.secrets."forgejo/token/normal".path}"
      dst="${storePath}/forgejo.ncaq.net/ncaq.gpg"
      $DRY_RUN_CMD mkdir -p "$(dirname "$dst")"
      if [ ! -e "$dst" ] \
         || ! ${pkgs.gnupg}/bin/gpg --batch --quiet --decrypt "$dst" 2>/dev/null \
              | ${pkgs.diffutils}/bin/cmp -s - "$src"; then
        $DRY_RUN_CMD ${pkgs.gnupg}/bin/gpg \
          --batch --yes --trust-model always \
          --encrypt --recipient ${PASSWORD_STORE_KEY} \
          --output "$dst" "$src"
      fi
    '';

    packages = [ pkgs.pass-git-helper ];
  };
}
