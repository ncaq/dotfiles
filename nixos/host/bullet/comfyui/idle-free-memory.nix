# アイドル中のComfyUIにメモリを解放させる常駐プロセスを、コンテナの中で動かす。
#
# 中身は`pkgs/comfyui-idle-free-memory`で、systemdのユニットもパッケージに同梱されている。
# 何をどう判断して解放するかはそちらの`src/IdleFreeMemory/Run.hs`の冒頭に書いてある。
#
# ホスト側のサービスにしない理由は寿命の管理である。
# ComfyUIのコンテナはソケットアクティベーションで起きるので、
# ホストに置くと`container@comfyui.service`への`bindsTo`と`after`と`wantedBy`で、
# 起動と停止を追従させる配線が要る。
# コンテナの中のサービスなら、コンテナが消える時に一緒に消える。
#
# 隔離の観点でも中に置いて構わない。
# 外部由来のコードと同じ空間へ自分のコードを入れることになるが、
# このプロセスが持つ権限はComfyUIのAPIを叩けることだけで、
# それは同じ空間にいるComfyUI自身が最初からできることである。
#
# 宛先がループバックになるので、
# vethのアドレスもコンテナのfirewallも関係しなくなる。
{ pkgs, ... }:
{
  containers.comfyui.config =
    { config, ... }:
    {
      # ホスト側の`pkgs`で組んだものを渡す。
      # コンテナの中もホストと同じnixpkgsなので、
      # `nixos/host/bullet/comfyui/workflow/cli.nix`が組むcomfy-workflowと依存の閉包を共有できる。
      systemd.packages = [ pkgs.comfyui-idle-free-memory ];
      systemd.services.comfyui-idle-free-memory = {
        # NixOSは`systemd.packages`のユニットの`[Install]`を見ないので、ここで有効にする。
        wantedBy = [ "multi-user.target" ];
        # ユニットの既定は8188なので今は同じ値だが、ポートを変えた時に追従させる。
        environment.COMFYUI_AUTHORITY = "[::1]:${toString config.services.comfyui.port}";
      };
    };
}
