{
  pkgs,
  lib,
  config,
  isTermux,
  ...
}:
lib.mkMerge [
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
  }
  (lib.mkIf (!isTermux) {
    # 起動時にキャッシュ設定を初期化します。
    systemd.user.services.attic-init = {
      Unit = {
        Description = "Initialize Attic Cache Configuration";
        Requires = [
          "sops-nix.service"
        ];
        After = [
          "sops-nix.service"
        ];
        ConditionPathExists = [ config.sops.secrets."attic-token".path ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        ExecStartPre = ''
          ${pkgs.curl}/bin/curl --head --silent --fail https://seminar.border-saurolophus.ts.net/nix/cache/
        '';
        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "attic-init";
            runtimeInputs = with pkgs; [
              attic-client
            ];
            text = ''
              attic login ncaq https://seminar.border-saurolophus.ts.net/nix/cache/ \
                < ${config.sops.secrets."attic-token".path}
              attic use ncaq:private
            '';
          }
        );
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  })
  (lib.mkIf isTermux {
    # Nix-on-Droid/Termux環境ではsystemdが動作しないため、
    # キャッシュ初期化はインストール時にactivation scriptで処理します。
    # Nix-on-Droidでactivationタイミングでパイプを処理するのは何故かうまくいかないので、
    # パイプではなく引数を使っています。
    # 引数を利用することで一瞬`ps`でトークンが見れる問題は、
    # セキュリティ上無視できる問題だと判断します。
    # Android端末で他人に`ps`を実行される権限があるのは問題外なので考慮しません。
    home.activation.attic-init = lib.hm.dag.entryAfter [ "sops-nix" ] ''
      if [[ -f "${config.sops.secrets."attic-token".path}" ]]; then
        # サーバーへの接続確認
        # すぐにタイムアウトするように短めに設定します
        if $DRY_RUN_CMD ${pkgs.curl}/bin/curl \
           --head --silent --fail --connect-timeout 5 --max-time 10 \
           https://seminar.border-saurolophus.ts.net/nix/cache/; then
          token=$(${pkgs.coreutils}/bin/cat ${config.sops.secrets."attic-token".path})
          $DRY_RUN_CMD ${pkgs.attic-client}/bin/attic login ncaq \
            https://seminar.border-saurolophus.ts.net/nix/cache/ \
            "$token"
          $DRY_RUN_CMD ${pkgs.attic-client}/bin/attic use ncaq:private
        else
          echo "attic-init: サーバーに接続できないためスキップします"
        fi
      else
        echo "attic-init: トークンファイルが存在しないためスキップします"
      fi
    '';
  })
]
