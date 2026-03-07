{
  pkgs,
  lib,
  config,
  hostName,
  username,
  ...
}:
let
  userConfig = config.users.users.${username};
in
lib.mkIf (hostName != "seminar") {
  # seminarサーバーのchihiro共有を手動マウントするための設定。
  # `sudo mount /mnt/chihiro`で手動マウント、
  # `sudo umount /mnt/chihiro`でアンマウント。
  fileSystems."/mnt/chihiro" = {
    device = "//seminar/chihiro";
    fsType = "cifs";
    options = [
      # 認証
      "credentials=${config.sops.templates."cifs-credentials".path}"
      "uid=${toString userConfig.uid}"
      "gid=${toString config.users.groups.${userConfig.group}.gid}"
      # ブート時に自動マウントしない
      "noauto"
      # マウント失敗時にブートをブロックしない
      "nofail"
      # ネットワークデバイス
      "_netdev"
      # セキュリティ
      "noexec"
      "nosuid"
      # パフォーマンス
      "noatime"
      # タイムアウトを短く設定しハング防止
      "x-systemd.device-timeout=5s"
      "x-systemd.mount-timeout=5s"
    ];
  };

  environment.systemPackages = with pkgs; [ cifs-utils ];

  sops = {
    templates."cifs-credentials" = {
      content = ''
        username=ncaq
        password=${config.sops.placeholder."cifs-password"}
      '';
      mode = "0400";
    };
    secrets."cifs-password" = {
      sopsFile = ../../secrets/samba.yaml;
      key = "password";
      mode = "0400";
    };
  };
}
