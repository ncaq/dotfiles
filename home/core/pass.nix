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

  # sopsで復号化したトークンをpassのエントリとして再暗号化して配置します。
  # 内容が変化した時のみ書き換えて実行の度に差分が出るのを避けます。
  syncForgejoTokenToPass = pkgs.writeShellApplication {
    name = "sync-forgejo-token-to-pass";
    runtimeInputs = with pkgs; [
      coreutils
      diffutils
      gnupg
    ];
    text = ''
      src="${config.sops.secrets."forgejo/token/normal".path}"
      dst="${storePath}/forgejo.ncaq.net/ncaq.gpg"
      mkdir -p "$(dirname "$dst")"
      if [ ! -e "$dst" ] || ! gpg --batch --quiet --decrypt "$dst" \
         | cmp -s - "$src"; then
        gpg \
          --batch --yes --trust-model always \
          --encrypt --recipient ${PASSWORD_STORE_KEY} \
          --output "$dst" "$src"
      fi
    '';
  };
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

  # boot時にsops-nixのシークレット展開が完了してからトークンを同期します。
  # boot時のactivationはシステムサービス経由で実行されるため、
  # ユーザのsystemdデーモンと同期できず、
  # activationスクリプトではシークレットの存在を保証できません。
  systemd.user.services.forgejo-token-to-pass = {
    Unit = {
      Description = "Sync Forgejo token from sops-nix secrets into pass";
      After = [ "sops-nix.service" ];
      Wants = [ "sops-nix.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe syncForgejoTokenToPass;
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  home = {
    # `pass init`の代わりに宣言的に`.gpg-id`を配置してストアを初期化します。
    # `pass-secret-service`が内部で使うプログラムは`PASSWORD_STORE_KEY`を読まず、
    # 起動時に`.gpg-id`の存在を必須とするため実ファイルの配置が避けられません。
    file."${storeRel}/.gpg-id".text = "${PASSWORD_STORE_KEY}\n";

    packages = [ pkgs.pass-git-helper ];
  };
}
