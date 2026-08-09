# GPUを触るサービスを常時起動させたくないので、
# ソケットアクティベーションによるオンデマンド起動にする。
{
  pkgs,
  config,
  hardening,
  ...
}:
{
  systemd = import ../../../../lib/container-socket-activation.nix {
    inherit pkgs hardening;
    container = "comfyui";
    label = "ComfyUI";
    localAddress = config.containers.comfyui.localAddress;
    port = config.containers.comfyui.config.services.comfyui.port;
    # ComfyUIには専用のヘルスチェック用エンドポイントがないのでルートを使う。
    healthPath = "/";
  };
}
