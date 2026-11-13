{
  lib,
  pkgs,
  options,
  ...
}:
lib.mkMerge [
  {
    # テスト環境ではネットワーク通信の認証をさせないのですが、
    # その場合Tailscale関係サービスが起動しようとかなり粘ってしまい、
    # テストが無意味に遅くなるので無効化しておきます。
    services.tailscale.enable = lib.mkForce false;

    # tailscaledを止めているので、
    # tailnetへの接続を待つ`tailscale-online.service`は決して終わりません。
    # 元の処理は`tailscale status`を繰り返し実行して失敗し続けるだけなので、
    # 何も実行せずに待たせます。
    # 失敗させずに待たせるのは、後ろに並ぶseminarのCIFSマウントなどを起動させないためです。
    # 起動させてもtailnetが無いので、到達の確認やマウントの失敗とリトライを繰り返すだけです。
    systemd.services.tailscale-online.serviceConfig.ExecStart =
      lib.mkForce "${pkgs.coreutils}/bin/sleep infinity";
  }
  # ホスト限定オプションなので分岐して無効化。
  (lib.optionalAttrs (options ? custom.tailscale-exit-node.enable) {
    custom.tailscale-exit-node.enable = lib.mkForce false;
  })
]
