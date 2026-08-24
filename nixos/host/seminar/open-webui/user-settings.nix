# Open WebUIの利用者ごとの設定を宣言してAPIで流し込む。
#
# `environment.nix`が扱うインスタンス全体の設定は`config`表に入り、
# 0.11.0ではその鍵の全てに対応する環境変数がある。
# 対してここで扱うのは`user`表の`settings`列に入るJSONで、
# 環境変数からは一切届かず、HTTP APIで書き込むしかない。
# 認証を無効にしていて利用者は一人しかいないが、
# 置き場としては利用者ごとのデータのままである。
#
# `ENABLE_PERSISTENT_CONFIG`が効くのは`config`表だけなので、
# こちらはDBへそのまま永続する。
# 環境変数のように毎回の起動で宣言が真になるわけではなく、
# 宣言と実体が一致するのはこの同期が走った時点だけである。
# UIから書き換えれば次にコンテナが起動するまで食い違ったままになる。
{
  lib,
  pkgs,
  config,
  username,
  hardening,
  ...
}:
let
  url = config.local.openWebui.url;

  # 人がブラウザで新しい会話を始めた時に既定で効くシステムプロンプト。
  #
  # home-managerはNixOSのホストではシステムへ統合されているため、
  # `lib/mk-nixos-system.nix`が読み込んだhome-manager側のオプションを直接引ける。
  # 素材を二重に持たずに、他のサービスへ貼るのと同じプロンプトを渡せる。
  #
  # 値はderivationなので、評価時に`readFile`で開くとIFDになる。
  # 同期のスクリプトが`jq --rawfile`で読めば評価は中身を知らずに済む。
  #
  # ミニ版を使うのは文字数の制約があるからではなく、
  # `blue-prompt.nix`が登録する人格のModelと合わさるためである。
  # `middleware.py`はModel側のシステムプロンプトを先に、
  # ブラウザが積んだこちらを後に連結するので、両方が同時に効く。
  # 人格を演じている最中にも噛み合う分量に絞っておきたい。
  systemPromptFile = config.home-manager.users.${username}.prompt.chatAssistantMini;

  # システムプロンプト以外に宣言する設定。
  #
  # ここに書いた鍵だけが上書きされ、書いていない鍵は実体のまま残る。
  # 全置換にしないのは、最後に選んだModelを覚える`models`のように、
  # 人が触った結果をそのまま持たせたい鍵が同じ階層に同居しているためである。
  #
  # `version`は書いてはならない。
  # `+layout.svelte`は`settings.version`が実際の版と異なる時に変更履歴を出すので、
  # 実際の版を宣言すると履歴が二度と出なくなり、
  # 固定の文字列を宣言すると閉じても同期で戻って毎回出続ける。
  declared = { };

  sync = pkgs.writeShellApplication {
    name = "open-webui-user-settings-sync";
    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      url=${lib.escapeShellArg url}

      # コンテナがbootした時点ではまだOpen WebUIはlistenしていない。
      # 埋め込みモデルの取得やDB migrationを伴う起動では待ち時間が長くなるため、
      # 接続が拒否される間も再試行して起動を待つ。
      curl --fail --silent --show-error --output /dev/null \
        --retry 30 --retry-delay 2 --retry-connrefused --max-time 10 \
        "$url/health"

      # `WEBUI_AUTH`を無効にしたインスタンスのadminとしてサインインする。
      # この組は`routers/auths.py`のsigninが無効時に使う定数そのもので、
      # 秘密ではなく、認証が無効である以上これ以外の資格情報は存在しない。
      token=$(
        curl --fail --silent --show-error --max-time 30 \
          --request POST "$url/api/v1/auths/signin" \
          --header 'Content-Type: application/json' \
          --data '{"email":"admin@localhost","password":"admin"}' |
          jq --raw-output '.token'
      )

      # curlは応答が2xxである限り成功するため、
      # 中身が期待した形でなかった場合はここで落としておく。
      # 空のトークンをそのまま使うと、
      # 認証の失敗ではなく設定の取得の失敗として現れて原因が分かりにくい。
      if [ -z "$token" ] || [ "$token" = null ]; then
        echo "サインインの応答からトークンを取り出せませんでした" >&2
        exit 1
      fi

      # Modelの登録と違い、この経路はトークンを要求する。
      current=$(
        curl --fail --silent --show-error --max-time 30 \
          --header "Authorization: Bearer $token" \
          "$url/api/v1/users/user/settings"
      )

      # 利用者の設定が一度も書かれていなければ応答はnullになる。
      #
      # ファイルの末尾の改行を落とすのは、
      # UIのテキストエリアが持つ値と揃えるためである。
      # 人が入力欄で書いた場合は末尾に改行が付かない。
      next=$(
        jq --null-input \
          --argjson current "$current" \
          --argjson declared ${lib.escapeShellArg (builtins.toJSON declared)} \
          --rawfile system ${systemPromptFile} \
          '(($current // {}).ui // {}) + $declared + { system: ($system | rtrimstr("\n")) }'
      )

      # 差分が無い時に書きに行かないのは、
      # コンテナが起動するたびに`updated_at`だけが進むのを避けるためである。
      if [ "$(jq --compact-output --sort-keys '(. // {}).ui // {}' <<<"$current")" = "$(jq --compact-output --sort-keys . <<<"$next")" ]; then
        echo "利用者の設定は宣言と一致しています"
        exit 0
      fi

      jq --null-input --argjson ui "$next" '{ ui: $ui }' |
        curl --fail --silent --show-error --max-time 30 --output /dev/null \
          --request POST "$url/api/v1/users/user/settings/update" \
          --header "Authorization: Bearer $token" \
          --header 'Content-Type: application/json' \
          --data @-
      echo "利用者の設定を宣言の内容へ更新しました"
    '';
  };
in
{
  systemd.services.open-webui-user-settings-sync = {
    description = "Sync declarative Open WebUI user settings";

    # Serviceがadvertiseされる前に同期が走ると名前を引けても接続先が居ない。
    requires = [ "tailscale-serve-open-webui.service" ];
    after = [
      "tailscale-serve-open-webui.service"
      "container@open-webui.service"
    ];

    # `blue-prompt.nix`と同じ理由でコンテナの起動と停止に追従させる。
    # `partOf`は明示的なstopやrestartのジョブでしか伝播しないため、
    # 異常終了して起動し直された場合に同期が`active (exited)`のまま取り残される。
    # `bindsTo`なら予期しない停止でも一度inactiveへ落ちて、
    # 次のコンテナ起動で確実に引き込み直される。
    wantedBy = [ "container@open-webui.service" ];
    bindsTo = [ "container@open-webui.service" ];

    serviceConfig = hardening.network // {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe sync;
      DynamicUser = true;

      # 恒久的に起動できない状態で短い間隔の再試行を繰り返さないよう、
      # `blue-prompt.nix`と同じ指数バックオフを使う。
      Restart = "on-failure";
      RestartSec = "1s";
      RestartMaxDelaySec = "2h";
      RestartSteps = 10;
    };
  };
}
