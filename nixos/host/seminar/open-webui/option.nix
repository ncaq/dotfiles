# Open WebUIのモジュール同士が共有する値を宣言するオプション。
# 型では表せない`environment`の制約の検査も、宣言の隣に置いてここで行う。
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

  options.local.openWebui.comfyuiPort = lib.mkOption {
    type = lib.types.port;
    readOnly = true;
    default = 8188;
    description = ''
      Open WebUIがComfyUIを探しに行くホスト側のポート。

      コンテナのvethのhostAddressでCaddyが待ち受けて、
      bulletのComfyUIへTailscale Service経由で中継する。
      コンテナは自分のnetnsを持っていてtailnetへの経路を持たないため、
      Service名を直接引くことはできない。

      値はComfyUI自身の既定のポートに合わせてあるが、
      待ち受けるのはseminarのホストなので衝突しない。

      接続先として使うのは`comfyuiUrl`の方で、
      こちらを直接引くのは待ち受けるCaddyとfirewallだけである。
    '';
  };

  options.local.openWebui.comfyuiUrl = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    default = "http://${config.machineAddresses.open-webui.host}:${toString config.local.openWebui.comfyuiPort}";
    defaultText = lib.literalMD ''
      コンテナのvethのhostAddressと`comfyuiPort`から組み立てたURL。
    '';
    description = ''
      コンテナのOpen WebUIから見たComfyUIの接続先。

      画像生成の`image-generation.nix`と画像編集の`image-edit.nix`が、
      それぞれ別の環境変数へ同じ値を渡す。
      `local.openWebui.url`と同じ理由でここに置く。
      それぞれが組み立てると、
      アドレスやポートを変えた時に片方だけ古い値を指したまま評価が通ってしまう。
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

  # 環境変数はユニットの`Environment=`に載るため、
  # 値の中の`%`はsystemdのspecifierとして展開される。
  # `%y`はユニットファイルのパスへ、`%m`はマシンIDへ、`%s`はシェルのパスへ変わる。
  #
  # 画像生成の`filename_prefix`に書いた`%year%`が実際にこれで壊れていて、
  # 出力されたファイル名を見るまで気付けなかった。
  # リテラルの`%`を渡すには`%%`と二重にする必要がある。
  #
  # 全ての値を横断して検査することで、
  # 今あるモジュールも将来足すモジュールも同じ保護を受けられる。
  config.assertions =
    let
      raw = lib.filterAttrs (
        _: value: lib.hasInfix "%" (lib.replaceStrings [ "%%" ] [ "" ] value)
      ) config.local.openWebui.environment;
    in
    [
      {
        assertion = raw == { };
        message = "local.openWebui.environmentの以下の値にsystemdのspecifierとして展開される`%`が含まれています。リテラルの`%`は`%%`と二重にしてください: ${lib.concatStringsSep ", " (lib.attrNames raw)}";
      }
    ];
}
