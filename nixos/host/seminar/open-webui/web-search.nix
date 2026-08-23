# Open WebUIのweb検索をOllama CloudのSearch APIで有効にする。
#
# エンジンの選択にあたって調べたことを残しておく。
#
# キーもホストも要らないのは`duckduckgo`だけだが、
# 中身はddgsライブラリによるスクレイピングで、
# 上流のDiscussionには並列数1かつ結果数3でも`202 Ratelimit`が出るという報告がある。
# ライブラリの複数のメジャーバージョンにまたがって続いていて、
# 一度弾かれるとIPが戻るまで待つしかない。
# SearXNGを自前で立てても裏でスクレイピングする点は変わらず、
# 日本語ではCAPTCHAの手動解除が要るという報告がある。
#
# 無料枠のある商用APIのうち、
# BraveのAPIは2026年2月に無料枠が廃止されてカード登録が必須になり、
# Google Programmable Search Engineは2026年1月から、
# 新規に作る検索エンジンでウェブ全体を対象にできなくなった。
#
# Ollama Cloudを選ぶのは、
# 既にOllamaのアカウントを使っていることと、
# 日本語のクエリで日本語のサイトが返るという利用報告があるためである。
# 無料枠の具体的な数値は公開されていないので、
# 足りなくなったら`WEB_SEARCH_ENGINE`を書き換えて別のエンジンへ移る。
{ config, ... }:
{
  local.openWebui.environment = {
    ENABLE_WEB_SEARCH = "True";
    WEB_SEARCH_ENGINE = "ollama_cloud";

    # 検索した結果を埋め込まず、取得した内容をそのままコンテキストへ入れる。
    #
    # 既定では拾ったページを埋め込んでベクタDBへ入れ、
    # そこから関連する断片を引き直す。
    # つまり検索のたびにコンテナのCPUでe5-largeが走ることになる。
    # 上流のモデルはcontextが131072あって、
    # ページ本文が1件あたり8000トークン程度に収まる以上、
    # 待ち時間を払ってまで絞り込む理由が無い。
    BYPASS_WEB_SEARCH_EMBEDDING_AND_RETRIEVAL = "True";

    # `BYPASS_WEB_SEARCH_WEB_LOADER`は既定の無効のままにする。
    # 検索結果のスニペットだけで答えさせず、
    # 実際にページを開いて本文を読ませたいため。

    # 既定の3から増やす。
    # 埋め込みを挟まないぶん本文がそのまま積み上がるが、
    # 1件8000トークンと見ても5件で4万程度なので、
    # 131072のcontextに対しては余裕がある。
    WEB_SEARCH_RESULT_COUNT = "5";
  };

  containers.open-webui = {
    # ホストのrootとしてsopsのシークレットを読み、コンテナPID 1のcredentialへ渡す。
    # privateUsersでUIDが変換されるため、
    # ホスト側のroot専用のファイルをそのままbindしてもコンテナからは読めない。
    extraFlags = [ "--load-credential=open-webui-env:${config.sops.templates."open-webui-env".path}" ];

    # コンテナのPID 1が受け取ったシステムクレデンシャルを直接読む。
    # `/run/credentials/@system`はコンテナ内でもroot専用なので、
    # open-webuiユーザを含む他のプロセスからは読めない。
    #
    # `LoadCredential`と`%d`の組み合わせを使わないのは、
    # systemdがサービス個別のcredentialディレクトリを用意するより前に、
    # EnvironmentFileを読み込むためである。
    # `comfyui`の`civitai.nix`も同じ理由で同じ形にしている。
    config.systemd.services.open-webui.serviceConfig.EnvironmentFile =
      "/run/credentials/@system/open-webui-env";
  };

  sops = {
    templates."open-webui-env" = {
      # Open WebUIはAPIキーを環境変数からしか読まないため、
      # シークレットそのものではなく環境変数の形をした一時ファイルを組み立てる。
      content = ''
        OLLAMA_CLOUD_API_KEY=${config.sops.placeholder."ollama-cloud-api-key"}
      '';
      restartUnits = [ "container@open-webui.service" ];
    };

    # placeholder参照のための宣言。
    # `/run/secrets`へ展開されるファイル自体はどこからも参照しない。
    secrets."ollama-cloud-api-key" = {
      sopsFile = ../../../../secrets/ollama.yaml;
      key = "cloud_api_key";
    };
  };
}
