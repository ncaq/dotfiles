# GPUを触るサービスを常時起動させたくないので、
# ソケットアクティベーションによるオンデマンド起動にする。
# `comfyui-proxy.socket`がホスト側でlistenし、
# 初回アクセス時にsystemd-socket-proxyd経由でコンテナごと起動する。
# アイドル時の自動停止は誤爆が怖いので設定しない。
# 停止したい時は手動で`systemctl stop container@comfyui.service`する。
{
  lib,
  pkgs,
  config,
  ...
}:
let
  port = config.containers.comfyui.config.services.comfyui.port;
  localAddress = config.containers.comfyui.localAddress;
in
{
  systemd = {
    services = {
      comfyui-proxy = {
        description = "systemd-socket-proxyd for on-demand ComfyUI activation";
        requires = [ "container@comfyui.service" ];
        after = [ "container@comfyui.service" ];
        serviceConfig = {
          # systemd-socket-proxydは`bin/`ではなく`lib/systemd/`に配置されるため、
          # `lib.getExe'`は使えない。
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd ${localAddress}:${toString port}";
          DynamicUser = true;
          PrivateTmp = true;
        };
      };
      "container@comfyui" = {
        # コンテナが起動してもComfyUIがlistenするまでは時間がかかり、
        # その前にproxydが接続すると初回リクエストが失敗してしまう。
        # HTTP疎通を確認してから起動完了扱いにする。
        postStart = ''
          until ${lib.getExe pkgs.curl} --fail --silent --output /dev/null "http://${localAddress}:${toString port}/"; do
            ${pkgs.coreutils}/bin/sleep 1
          done
        '';
      };
    };
    sockets.comfyui-proxy = {
      description = "Socket for on-demand ComfyUI activation";
      listenStreams = [
        "127.0.0.1:${toString port}"
        "[::1]:${toString port}"
      ];
      wantedBy = [ "sockets.target" ];
    };
  };
}
