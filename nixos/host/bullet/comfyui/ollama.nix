# ComfyUIのコンテナからOllamaへ届く経路を用意する。
#
# 指示文のリライトを自作ノードからOllamaへ投げるために要る。
#
# Ollamaのコンテナへ`localAddress`で直接繋ぐことはできるが、
# それでは`ollama-proxy.socket`を迂回するのでオンデマンド起動が効かない。
# `container@ollama`が動いていない状態、
# 例えば起動してから一度もOllamaを使っていない状態では単に失敗する。
#
# かといってTailscale Serviceの名前も使えない。
# ComfyUIのコンテナは自分のnetnsを持っていて、
# MagicDNSの100.100.100.100もtailnetのULAへの経路も持たないため、
# `ollama-bullet.<tailnet>`は名前解決もTCP接続もできないことを確認済み。
#
# そこでsocketの待ち受けに、
# ComfyUIコンテナ用vethのホスト側のアドレス(`hostAddress`)を足して、
# ホスト内で完結したままオンデマンド起動を効かせる。
# コンテナ側の`localAddress`ではない。
# 足すのはあくまでホストが待ち受けるアドレスである。
#
# 待ち受けアドレスを増減させた時は`./install.sh`だけでは反映されない。
# systemdは動作中のsocketユニットへ後からFDを足さず、
# 「Unit configuration changed while unit was running」と警告して古い口のまま動き続ける。
# しかも`ollama-proxy.service`が動いている間は、
# 「Socket service ollama-proxy.service already active, refusing」でrestartを拒否する。
# 反映するにはserviceを止めてからsocketをrestartする。
#
# ```console
# sudo systemctl stop ollama-proxy.service
# sudo systemctl restart ollama-proxy.socket
# ```
{ config, ... }:
let
  hostAddress = config.containers.comfyui.hostAddress;
  port = config.containers.ollama.config.services.ollama.port;
  url = "http://${hostAddress}:${toString port}";
in
{
  systemd.sockets.ollama-proxy = {
    # `lib/container-socket-activation.nix`が置くループバックの待ち受けに足す。
    # `hostAddress`はveth pairのホスト側なので、待ち受けるのはホスト自身である。
    listenStreams = [ "${hostAddress}:${toString port}" ];
    socketConfig = {
      # `ve-comfyui`はComfyUIのコンテナが動いている間しか存在しない。
      # ComfyUI自身もオンデマンド起動なので、
      # このsocketがbindする時点でアドレスが無いことの方が普通である。
      # FreeBindが無いと起動時にbindへ失敗してsocket自体が上がらない。
      FreeBind = true;
    };
  };

  # ComfyUIコンテナのvethからこの待ち受けへの接続を許可する。
  # 開くのは認証の無いOllamaなので、`ve-+`のワイルドカードでは開けない。
  # ホストのFORWARDはACCEPTなので、
  # 他のコンテナで動く外部由来のコードからも到達できてしまう。
  networking.firewall.interfaces."ve-comfyui".allowedTCPPorts = [ port ];

  # 接続先をコンテナの中の自作ノードへ渡す。
  # アドレスはNixが組み立てるので、Python側にIPもポートも書かない。
  containers.comfyui.config = {
    systemd.services.comfyui.environment.COMFYUI_OLLAMA_URL = url;
  };
}
