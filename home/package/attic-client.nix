{
  pkgs,
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
  };

  # 起動時にキャッシュ設定を初期化します。
  systemd.user.services.attic-init = {
    Unit = {
      Description = "Initialize Attic Cache Configuration";
      Wants = [
        "network-online.target"
        "nss-lookup.target"
      ];
      After = [
        "network-online.target"
        "nss-lookup.target"
      ];
      Before = [
        "attic-watch-store-ncaq-private.service"
      ];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ConditionPathExists = [ config.sops.secrets."attic-token".path ];
      ExecStartPre = ''
        ${pkgs.curl}/bin/curl \
          --head --silent --fail \
          --connect-timeout 10 --max-time 30 \
          --retry 3 --retry-delay 10 --retry-all-errors \
          https://cache.nix.ncaq.net/
      '';
      ExecStart = pkgs.writeShellApplication {
        name = "attic-init";
        runtimeInputs = with pkgs; [
          attic-client
        ];
        text = ''
          attic login ncaq https://cache.nix.ncaq.net/ < ${config.sops.secrets."attic-token".path}
          attic use ncaq:private
        '';
      };
      # 失敗時に自動リトライします。
      Restart = "on-failure";
      RestartSec = "30s";
      TimeoutStartSec = "5min";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # 全てのビルド結果を非同期にプライベートキャッシュにpushします。
  systemd.user.services.attic-watch-store-ncaq-private = {
    Unit = {
      Description = "Attic Binary Cache Auto-Push Service for ncaq:private";
      # ネットワークなどの準備が整ってから起動します。
      Requires = [ "attic-init.service" ];
      After = [
        "network-online.target"
        "nix-daemon.service"
        "attic-init.service"
      ];
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
