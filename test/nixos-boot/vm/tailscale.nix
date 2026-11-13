{
  lib,
  options,
  username,
  ...
}:
lib.mkMerge [
  {
    # テスト環境ではネットワーク通信の認証をさせないのですが、
    # その場合Tailscale関係サービスが起動しようとかなり粘ってしまい、
    # テストが無意味に遅くなるので無効化しておきます。
    services.tailscale.enable = lib.mkForce false;
    home-manager.users.${username}.services.trayscale.enable = lib.mkForce false;
  }
  # ホスト限定オプションなので分岐して無効化。
  (lib.optionalAttrs (options ? custom.tailscale-exit-node.enable) {
    custom.tailscale-exit-node.enable = lib.mkForce false;
  })
]
