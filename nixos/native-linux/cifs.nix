{
  pkgs,
  config,
  ...
}:
let
  userConfig = config.users.users.ncaq; # サーバ側がユーザ名`ncaq`を求めるため固定します
  uid = toString userConfig.uid;
  gid = toString config.users.groups.${userConfig.group}.gid;
in
{
  environment.systemPackages = with pkgs; [ cifs-utils ];

  sops.secrets."cifs-password" = {
    sopsFile = ../../secrets/samba.yaml;
    key = "password";
    mode = "0400";
  };

  sops.templates."cifs-credentials" = {
    content = ''
      username=ncaq
      password=${config.sops.placeholder."cifs-password"}
    '';
    mode = "0400";
  };

  fileSystems."/mnt/chihiro" = {
    fsType = "cifs";
    device = "//seminar/chihiro";
    options = [
      "noatime"
      "uid=${uid}"
      "gid=${gid}"
      "_netdev"
      "nofail"
      "noexec"
      "nosuid"
      "credentials=${config.sops.templates."cifs-credentials".path}"
    ];
  };
}
