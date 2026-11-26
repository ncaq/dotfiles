{
  config,
  username,
  ...
}:
{
  # tcpdumpをpcapグループで実行できるようにする。
  programs.tcpdump.enable = true;
  # 通常使うユーザをtcpdumpを実行できるグループに所属させる。
  users.users.${username}.extraGroups = [ config.security.wrappers.tcpdump.group ];
}
