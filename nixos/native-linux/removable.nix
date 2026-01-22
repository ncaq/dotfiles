# 使っているリムーバブルストレージのうち暗号化していないものを記述
{ config, username, ... }:
let
  userConfig = config.users.users.${username};
  uid = toString userConfig.uid;
  gid = toString config.users.groups.${userConfig.group}.gid;
in
{
  fileSystems = {
    "/mnt/turugi" = {
      device = "/dev/disk/by-label/turugi";
      fsType = "exfat";
      options = [
        "noatime"
        "uid=${uid}"
        "gid=${gid}"
        "noauto"
      ];
    };
  };
  systemd.tmpfiles.rules = [
    "d /mnt/turugi 0755 root root -"
  ];
}
