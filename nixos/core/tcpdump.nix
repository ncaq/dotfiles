{
  config,
  username,
  ...
}:
{
  # tcpdumpをpcapグループで実行できるようにする。
  programs.tcpdump.enable = true;
  # 通常使うユーザをtcpdumpの実行可能ユーザに所属させる。
  users.users.${username}.extraGroups = [ config.security.wrappers.tcpdump.group ];
}
