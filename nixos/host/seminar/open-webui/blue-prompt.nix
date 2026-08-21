# blue-promptのスキルから生成したワークスペースModelとKnowledgeをOpen WebUIへ登録する。
#
# Open WebUIにはスキルのオンデマンド読み込みが無いため、
# 人格を与えるスキルは内容をシステムプロンプトへ焼き込んだModelとして事前に登録し、
# 事実を引くだけのスキルはModelから参照できるKnowledgeとして登録しておく。
# どちらも他のチャット履歴と同じくOpen WebUIのDBに持つ状態なので、
# Nixで宣言できるのは同期を行うサービスの側だけになる。
{
  lib,
  config,
  inputs,
  ...
}:
let
  serve = config.local.tailscaleServe.services.open-webui;
  # `tailscale-serve.nix`が公開しているのと同じ、人がブラウザで開くURL。
  # Tailscale Serveの転送先はホスト側のsocket proxyなので、
  # loopbackを直接叩くのと最終的な到達先もコンテナから見える送信元も変わらない。
  # 同じホストからの接続でも経路はtailscaledの中で完結する。
  url = "https://${lib.removePrefix "svc:" serve.service}.${config.local.tailscale.tailnet}";
in
{
  imports = [ inputs.blue-prompt.nixosModules.default ];

  blue-prompt.open-webui = {
    enable = true;
    inherit url;
    # 推論に使う上流モデル。
    # 拒否挙動を除去してあるので、
    # キャラクターの人格を演じるスキルが安全側へ倒れて崩れることが少ない。
    baseModelId = "qwen3.8-27b-heretic-rvn:q4_k_m";
    # コンテナのOpen WebUIは`WEBUI_AUTH = "False"`で動いているため、
    # APIキーを渡さなくても書き込みできる。
  };

  systemd.services.blue-prompt-open-webui-sync = {
    # Serviceがadvertiseされる前に同期が走ると名前を引けても接続先が居ない。
    # Serveの登録はRemainAfterExitのoneshotなので、
    # afterで完了まで待てば初回アクセスでコンテナのsocket activationも発火する。
    requires = [ "tailscale-serve-open-webui.service" ];
    after = [
      "tailscale-serve-open-webui.service"
      "container@open-webui.service"
    ];
    # RAGのプロンプトテンプレートはインスタンス全体の設定としてAPIで書き込まれる。
    # コンテナは`ENABLE_PERSISTENT_CONFIG = "False"`で動いていて、
    # この種の設定はDBへ残らずプロセス内にしか無いため、
    # コンテナが再起動するとOpen WebUI標準の英語のテンプレートへ戻ってしまう。
    # 同期はRemainAfterExitのoneshotなので放っておくと再実行されず、
    # 人格側のModelの話し方が壊れたまま気付かれずに残る。
    # コンテナの起動と停止に追従させて、その度に同期をやり直す。
    #
    # コンテナは`autoStart = false`でsocket activationから起動するため、
    # boot時のトランザクションにはコンテナのジョブが無く`after`は効かない。
    # 従来どおり同期自身のアクセスがsocket activationを発火させる。
    wantedBy = [ "container@open-webui.service" ];
    partOf = [ "container@open-webui.service" ];
    # Knowledgeのアップロードでは1ファイルごとに埋め込みがコンテナ内で走る。
    # 断片の数だけ時間が積み上がるため、
    # oneshotの既定のタイムアウトで中断されて中途半端な状態が残るのを念のため避ける。
    #
    # 上限を外さないのは、
    # このユニットがoneshotでmulti-user.targetに紐付いているためで、
    # 同期が詰まるとboot時のtarget到達と`./install.sh`のactivationが待ち続けてしまう。
    # 同期側はリクエストごとに.NETの既定の100秒で打ち切るので、
    # 断片の数から全体の上限も見積もれる。
    # 余裕を持った有限値にしておけば、
    # 想定を超えた時はfailとしてジャーナルに残って気付ける。
    serviceConfig.TimeoutStartSec = "1h";
  };
}
