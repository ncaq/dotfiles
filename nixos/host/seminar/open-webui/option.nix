# Open WebUIのモジュール同士が共有する値を宣言するオプション。
{ lib, config, ... }:
{
  options.local.openWebui.url = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "https://${lib.removePrefix "svc:" config.local.tailscaleServe.services.open-webui.service}.${config.local.tailscale.tailnet}";
    defaultText = lib.literalMD ''
      `tailscaleServe`のService名とtailnetのMagicDNSのsuffixから組み立てたURL。
    '';
    description = ''
      人がブラウザで開くOpen WebUIのURL。

      `tailscale-serve.nix`が公開しているのと同じ名前を指す。
      Tailscale Serveの転送先はホスト側のCaddyなので、
      loopbackを直接叩くのと最終的な到達先もコンテナから見える送信元も変わらない。
      同じホストからの接続でも経路はtailscaledの中で完結する。

      Open WebUI自身へ渡す`WEBUI_URL`と、
      APIを叩きに行く同期の接続先の両方がこの値を必要とする。
      それぞれが組み立てると、
      Service名を変えた時に片方だけ古い名前を指したまま評価が通ってしまう。
    '';
  };

  options.local.openWebui.ollamaPort = lib.mkOption {
    type = lib.types.port;
    readOnly = true;
    default = 11434;
    description = ''
      Open WebUIがOllamaを探しに行くホスト側のポート。
      コンテナのvethのhostAddressでCaddyが待ち受けて、
      bulletとseminarのOllamaへ優先順位付きで振り分ける。
      ホストのloopbackで待つOllamaのproxyとはbindアドレスが違うので衝突しない。
    '';
  };

  options.local.openWebui.environment = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = ''
      コンテナのOpen WebUIへ渡す環境変数。

      本来はUIの管理画面や設定画面から触る類の設定を、
      Nixの側で宣言しておくために使う。
      コンテナは`ENABLE_PERSISTENT_CONFIG = "False"`で動いていて、
      設定の読み取りが常に環境変数から作った既定値を向くため、
      ここに書いた値が毎回の起動でそのまま効く。

      コンテナの構造そのものを決める変数は`container.nix`が直接書く。
      あちらの定義が後に来るので、ここへ同じキーを書いても上書きはできない。
    '';
  };
}
