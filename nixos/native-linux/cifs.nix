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
  # seminarサーバーのchihiro共有を自動マウントするための設定。
  # ネットワーク、Tailscale、sopsシークレットが揃った時点でマウントを試行する。
  # nofailにより失敗してもブートをブロックしない。
  fileSystems."/mnt/chihiro" = {
    device = "//seminar/chihiro";
    fsType = "cifs";
    options = [
      # 認証
      "credentials=${config.sops.templates."cifs-credentials".path}"
      "uid=${toString userConfig.uid}"
      "gid=${toString config.users.groups.${userConfig.group}.gid}"
      # ネットワーク依存(network-online.targetを自動追加)
      "_netdev"
      # sopsシークレットとTailscaleとの準備完了後にマウント
      "x-systemd.after=sops-install-secrets.service"
      "x-systemd.after=tailscaled.service"
      # マウントタイムアウト
      "x-systemd.mount-timeout=30"
      # マウント失敗時にブートをブロックしない
      "nofail"
      # セキュリティ
      "nodev"
      "noexec"
      "nosuid"
      # パフォーマンス
      "noatime"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /mnt/chihiro 0000 root root -"
  ];

  environment.systemPackages = with pkgs; [ cifs-utils ];

  sops = {
    templates."cifs-credentials" = {
      # サーバ側が固定でユーザ名`ncaq`を期待しているのでハードコーディングしています。
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
