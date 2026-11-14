# テストVMには秘密情報が無いので、起動に必ず失敗するユニットがあります。
# そのうち`Restart=`で再起動するものは、
# 起動の回数の制限に掛かるまで同じ理由の失敗を繰り返し、
# ブート中のCPUを他のユニットと奪い合うだけです。
# 1回失敗したら諦めさせます。
#
# ユニットごと無効化しないのは、
# 無効化すると依存するユニットからは失敗ではなく存在しないユニットに見えるからです。
# 秘密情報が無いテストVMで起きる失敗を、そのまま残します。
#
# 他のユニットから依存されていない、
# 必ず失敗するだけのユニットは無効化します。
# 失敗がログに残るだけのノイズで、無効化しても他のユニットの振る舞いは変わりません。
{ lib, config, ... }:
let
  noRestart = {
    serviceConfig.Restart = lib.mkForce "no";
  };
  disabled = {
    enable = false;
  };
in
{
  systemd.services =
    # Cloudflare Tunnelの資格情報は全てsopsから渡しています。
    lib.mapAttrs' (
      name: _: lib.nameValuePair "cloudflared-tunnel-${name}" noRestart
    ) config.services.cloudflared.tunnels
    # 認証の設定を環境変数のファイルで渡しています。
    // lib.optionalAttrs config.services.opentelemetry-collector.enable {
      opentelemetry-collector = noRestart;
    }
    # 秘密情報から作る環境変数のファイルを起動前に複製します。
    # GarageをS3の保存先にするコンテナも、これに依存して起動に失敗します。
    // lib.optionalAttrs (config.containers ? garage) {
      "container@garage" = noRestart;
    }
    # 秘密情報から作る環境変数のファイルを資格情報としてコンテナへ渡しています。
    // lib.optionalAttrs (config.containers ? open-webui) {
      "container@open-webui" = noRestart;
    }
    # Sambaのパスワードを秘密情報から読んで登録します。
    # oneshotなので再起動はせず、smbdもこれを待たずに起動します。
    // lib.optionalAttrs config.services.samba.enable {
      samba-password-setup = disabled;
    };
}
