{ config, ... }:
{
  # サーバはヘッドレス運用なので、tailscaledが故障した時の復旧経路として、
  # tailnet限定(`nixos/core/ssh.nix`)に加えてLANからのssh/moshも受け付ける。
  #
  # 全インターフェイスに開けるのではなくLANのインターフェイスに限定するのは、
  # コンテナのvethやmicroVMのTAPからホストのsshdへ届かせないため。
  # CIランナーのようにリポジトリのコードが動くコンテナから、
  # 認証が必要とはいえホストのSSHに触れる理由は無い。
  #
  # `local.lan`はseminarの`lan.nix`が宣言しているオプションで、
  # server層を取り込むホストは今のところseminarだけなのでそのまま参照する。
  networking.firewall.interfaces.${config.local.lan.interface} = config.local.ssh.firewallRule;
}
