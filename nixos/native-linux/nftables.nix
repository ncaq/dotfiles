{ lib, config, ... }:
let
  # iptables時代の`ve-+`のようなワイルドカードは、
  # nftablesではその名前そのものへの一致になって評価もビルドも通ったまま何にも合わない。
  # iptables向けの資料から写した時の退行を評価時に止める。
  endsWithPlus = lib.hasSuffix "+";
  plusInternalInterfaces = lib.filter endsWithPlus config.networking.nat.internalInterfaces;
  plusFirewallInterfaces = lib.filter endsWithPlus (
    lib.attrNames config.networking.firewall.interfaces
  );
in
{
  # firewallとNATのバックエンドをnftablesにする。
  #
  # カーネル側はNixOS 21.11からiptablesコマンド自体がiptables-nftなので、
  # 既にnf_tablesで動いている。
  # 変わるのはNixOSのモジュールがルールを組み立てる言語で、
  # `extraInputRules`や`extraForwardRules`や`filterForward`のような、
  # 新しい設定項目はnftablesバックエンドにしか無い。
  #
  # 他のモジュールはnftablesを前提にして書く。
  # 特にインターフェイス名のワイルドカードは`ve-*`で、
  # iptables時代の`ve-+`はnftablesではその名前そのものへの一致になって何にも合わない。
  #
  # WSLはNixOS-WSLがfirewall自体を無効にしているので対象外。
  #
  # rootless Dockerはユーザのネットワーク名前空間の中でiptables-nftを呼ぶだけで、
  # ホストのルールには触らない。
  # このモジュールが`ip_tables`カーネルモジュールを読み込み禁止にしても、
  # iptables-nftはnf_tablesを使うので影響しない。
  networking.nftables.enable = true;

  assertions = [
    {
      assertion = plusInternalInterfaces == [ ];
      message = "networking.nat.internalInterfaces contains iptables-style wildcards ${toString plusInternalInterfaces}; nftables wildcards end with `*`, not `+`";
    }
    {
      assertion = plusFirewallInterfaces == [ ];
      message = "networking.firewall.interfaces contains iptables-style wildcards ${toString plusFirewallInterfaces}; nftables wildcards end with `*`, not `+`";
    }
  ];
}
