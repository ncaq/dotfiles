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
  home.activation.attic-init = lib.hm.dag.entryAfter [ "sops-nix" ] ''
    if [[ -f "${config.sops.secrets."attic-token".path}" ]]; then
      # サーバーへの接続確認
      if ${pkgs.curl}/bin/curl \
         --head --silent --fail \
         --connect-timeout 5 --max-time 10 \
         https://seminar.border-saurolophus.ts.net/nix/cache/; then
        # デバッグ
        echo "attic-init: HOME = $HOME"
        echo "attic-init: token path = ${config.sops.secrets."attic-token".path}"
        echo "attic-init: token head = $(${pkgs.coreutils}/bin/head -c 20 ${
          config.sops.secrets."attic-token".path
        })"
        ${pkgs.coreutils}/bin/cat ${config.sops.secrets."attic-token".path} | \
          ${pkgs.attic-client}/bin/attic login ncaq https://seminar.border-saurolophus.ts.net/nix/cache/
        ${pkgs.attic-client}/bin/attic use ncaq:private
      else
        echo "attic-init: サーバーに接続できないためスキップします"
      fi
    else
      echo "attic-init: トークンファイルが存在しないためスキップします"
    fi
  '';
}
