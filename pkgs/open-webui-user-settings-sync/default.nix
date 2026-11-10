# Open WebUIの利用者ごとの設定とプロフィールを、宣言した内容へ揃えるコマンド。
#
# `nixos/host/seminar/open-webui/user-settings.nix`のサービスから呼ばれます。
# 何をするかと必要な環境変数は`open-webui-user-settings-sync.bash`の冒頭に書いてあります。
#
# 設定をマージするjqのフィルタは`user-settings-merge.jq`にあり、
# `merge-test.nix`が同じファイルを検査します。
# フィルタは`$out`へ入れてラッパーからパスで渡すので、
# 実機のクロージャに含まれてGCで消えることはありません。
{
  lib,
  runCommand,
  makeWrapper,
  shellcheck,
  coreutils,
  curl,
  jq,
}:
runCommand "open-webui-user-settings-sync"
  {
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
    meta.mainProgram = "open-webui-user-settings-sync";
  }
  ''
    shellcheck ${./open-webui-user-settings-sync.bash}
    install -Dm755 ${./open-webui-user-settings-sync.bash} \
      $out/libexec/open-webui-user-settings-sync/open-webui-user-settings-sync.bash
    install -Dm644 ${./user-settings-merge.jq} \
      $out/share/open-webui-user-settings-sync/user-settings-merge.jq
    # systemdのサービスのPATHにはbashが無いので、`env`で探させずストアのbashへ固定します。
    patchShebangs $out/libexec
    makeWrapper $out/libexec/open-webui-user-settings-sync/open-webui-user-settings-sync.bash \
      $out/bin/open-webui-user-settings-sync \
      --set OPEN_WEBUI_USER_SETTINGS_MERGE_FILTER \
        $out/share/open-webui-user-settings-sync/user-settings-merge.jq \
      --prefix PATH : ${
        lib.makeBinPath [
          # `base64`のために要る。
          coreutils
          curl
          jq
        ]
      }
  ''
