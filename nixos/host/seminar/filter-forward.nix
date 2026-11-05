_: {
  # FORWARDをフィルタする。
  # 既定ではコンテナやmicroVMのvethからの転送が無条件に通っていて、
  # 転送先がLANでもtailnetでも区別が無かった。
  # 有効にするとforwardチェインのpolicyがdropになり、
  # NATモジュールが`internalInterfaces`からのacceptを自動で足す。
  # それ以外に転送を許したい経路(exit nodeなど)は`extraForwardRules`で明示する。
  networking.firewall.filterForward = true;
}
