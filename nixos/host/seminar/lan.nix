{ lib, ... }:
{
  # 自宅LANの情報。
  # NetworkManagerにDHCPで任せているので`networking.interfaces`には宣言が無く、
  # NixOSのoptionからインターフェイス名を引く手段が無い。
  # LANにだけ開けたいfirewallやサービスのbind先が各所で同じ文字列を繰り返さないように、
  # ここを単一の出典にする。
  options.local.lan = {
    interface = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "enp7s0";
      description = ''
        自宅LANに繋がる物理NICのインターフェイス名。
        systemdのpredictable network interface namesによるPCIスロット由来の名前なので、
        NICを別のスロットへ差し替えたりマザーボードを替えたりすると変わる。
      '';
    };
    ipv4Subnet = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "192.168.10.0/24";
      description = ''
        自宅LANのIPv4サブネット。
        ルータのDHCPが配る範囲で、`interface`にはこの範囲のアドレスが付く。
      '';
    };
  };
}
