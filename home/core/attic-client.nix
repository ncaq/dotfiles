{
  pkgs,
  lib,
  config,
  ...
}:
{
  # atticのJWTトークンをsops-nixで管理します。
  # トークンの更新: `sops secrets/attic-client.yaml`
  # トークンはサーバ側で発行してください。
  # [atticd](../../nixos/host/seminar/atticd.nix)
  sops.secrets."attic-token" = {
    sopsFile = ../../secrets/attic-client.yaml;
    key = "token";
    mode = "0400";
  };

  # インストール時にキャッシュ設定を初期化します。
  home.activation.attic-init = lib.hm.dag.entryAfter [ "sopsNix" ] ''
    if [[ -f "${config.sops.secrets."attic-token".path}" ]]; then
      # サーバーへの接続確認
      if $DRY_RUN_CMD ${pkgs.curl}/bin/curl \
         --head --silent --fail \
         --connect-timeout 5 --max-time 10 \
         https://seminar.border-saurolophus.ts.net/nix/cache/; then
        $DRY_RUN_CMD ${pkgs.attic-client}/bin/attic login ncaq \
          https://seminar.border-saurolophus.ts.net/nix/cache/ < \
          ${config.sops.secrets."attic-token".path}
        $DRY_RUN_CMD ${pkgs.attic-client}/bin/attic use ncaq:private
      else
        echo "attic-init: サーバーに接続できないためスキップします"
      fi
    else
      echo "attic-init: トークンファイルが存在しないためスキップします"
    fi
  '';

  # 全てのビルド結果を非同期にプライベートキャッシュにpushします。
  systemd.user.services.attic-watch-store-ncaq-private = {
    Unit = {
      Description = "Attic Binary Cache Auto-Push Service for ncaq:private";
      # ネットワークなどの準備が整ってから起動します。
      After = [
        "network-online.target"
        "nix-daemon.service"
      ];
      # 設定ファイルが存在しない場合は起動しません。
      ConditionPathExists = [ "%h/.config/attic/config.toml" ];
    };

    Service = {
      # クラッシュしてもしばらく後に再起動します。
      Restart = "on-failure";
      RestartSec = "15s";

      # 必要なパスのみアクセス許可します。
      ReadOnlyPaths = [
        "/nix/store"
        "%h/.config/attic"
      ];
      # 直接コマンド実行
      ExecStart = "${pkgs.attic-client}/bin/attic watch-store ncaq:private";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };
}
