_: {
  # firewallとNATのバックエンドをnftablesにする。
  #
  # カーネル側はNixOS 21.11からiptablesコマンド自体がiptables-nftなので、
  # 既にnf_tablesで動いている。
  # 変わるのはNixOSのモジュールがルールを組み立てる言語で、
  # `extraInputRules`や`extraForwardRules`や`filterForward`のような、
  # 新しい設定項目はnftablesバックエンドにしか無い。
  # iptablesバックエンドではこれらは黙って無視される。
  #
  # Dockerを使っているホストではDockerがiptablesを直接叩くので注意が要るが、
  # seminarにはDockerは無い。
  networking = {
    nftables.enable = true;
    # FORWARDをフィルタする。
    # 既定ではコンテナやmicroVMのvethからの転送が無条件に通っていて、
    # 転送先がLANでもtailnetでも区別が無かった。
    # 有効にするとforwardチェインのpolicyがdropになり、
    # NATモジュールが`internalInterfaces`からのacceptを自動で足す。
    # それ以外に転送を許したい経路(exit nodeなど)は`extraForwardRules`で明示する。
    firewall.filterForward = true;
  };
}
