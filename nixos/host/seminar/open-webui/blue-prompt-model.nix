# blue-promptのスキルから生成したワークスペースModelをOpen WebUIへ登録する。
#
# Open WebUIにはスキルのオンデマンド読み込みが無いため、
# スキルの内容をシステムプロンプトへ焼き込んだModelとして事前に登録しておく。
# Modelは他のチャット履歴と同じくOpen WebUIのDBに持つ状態なので、
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

  # Serviceがadvertiseされる前に同期が走ると名前を引けても接続先が居ない。
  # Serveの登録はRemainAfterExitのoneshotなので、
  # afterで完了まで待てば初回アクセスでコンテナのsocket activationも発火する。
  systemd.services.blue-prompt-open-webui-model-sync = {
    requires = [ "tailscale-serve-open-webui.service" ];
    after = [ "tailscale-serve-open-webui.service" ];
  };
}
