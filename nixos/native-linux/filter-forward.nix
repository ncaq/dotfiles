_: {
  # FORWARDをフィルタする。
  # 既定ではforwardチェインのpolicyがacceptで、
  # NATモジュールがIPv4とIPv6の転送を有効にした時点で、
  # LAN、tailscale0、コンテナのvethの間をホストが無条件に中継する。
  # 有効にするとforwardチェインのpolicyがdropになり、
  # NATモジュールが`internalInterfaces`からのacceptを自動で足す。
  # それ以外に転送を許したい経路は各ホストが`extraForwardRules`で明示する。
  # seminarのexit nodeがその例。
  #
  # `internalInterfaces`からの転送はこのacceptで全て通るが、
  # その手前で`nixos/native-linux/machine-egress.nix`がマシンごとの許可リストに絞っている。
  #
  # コンテナを持つのはseminarとbulletだが、全てのネイティブLinuxホストで有効にする。
  # 転送を必要とするものが無いホストで転送が通る理由が無く、
  # 後からコンテナやNATを足した時に黙って全開のまま動くのを防ぐため。
  networking.firewall.filterForward = true;
}
