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
}
