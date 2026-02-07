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
  # Nix-on-Droidで何故かうまくいかないので、
  # パイプではなく引数を使っています。
  # 引数を利用することで一瞬`ps`でトークンが見れる問題は、
  # セキュリティ上無視できる問題だと判断します。
  # そもそも`ps`を実行される権限があるのが問題外と考えます。
  home.activation.attic-init = lib.hm.dag.entryAfter [ "sops-nix" ] ''
    if [[ -f "${config.sops.secrets."attic-token".path}" ]]; then
      # サーバーへの接続確認
      if $DRY_RUN_CMD ${pkgs.curl}/bin/curl \
         --head --silent --fail \
         --connect-timeout 5 --max-time 10 \
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
}
