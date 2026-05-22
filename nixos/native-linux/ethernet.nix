{ ... }:
{
  networking.networkmanager.ensureProfiles.profiles = {
    # NetworkManagerのプロファイルの自動生成を無効化して宣言的管理に寄せているため、
    # ベーシックなEthernetプロファイルも明示的に宣言する必要があります。
    basic-ethernet = {
      connection = {
        id = "basic-ethernet";
        uuid = "1d498986-7538-4a96-8484-5bdb1b9c6e34";
        type = "ethernet";
        # 大抵のethernetでは事情は概ね同じだと思うので、
        # interface-nameは敢えて指定しません。
        # 複雑な設定を持つものだけ個別設定します。
      };
      ivp4 = {
        method = "auto";
      };
      ipv6 = {
        addr-gen-mode = "default";
        method = "auto";
      };
    };
  };
}
