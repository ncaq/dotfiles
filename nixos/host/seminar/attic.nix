{ username, ... }:
{
  services.atticd = {
    enable = true;
    # ```
    # echo -n 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64="'|sudo tee /etc/atticd.env
    # openssl genrsa -traditional 4096|base64 -w0|sudo tee -a /etc/atticd.env
    # echo '"'|sudo tee -a /etc/atticd.env
    # sudo chown atticd: /etc/atticd.env && sudo chmod 640 /etc/atticd.env
    # ```
    environmentFile = "/etc/atticd.env";
    settings = {
      listen = "[::]:10000"; # ポート番号は雑に定めました。深く考えていません。
      allowed-hosts = [ "nix-cache.ncaq.net" ];
      api-endpoint = "https://nix-cache.ncaq.net/";
      database.url = "postgresql:///atticd?host=/run/postgresql";
      storage = {
        type = "local";
        path = "/mnt/noa/atticd";
      };
      # chunkingはNixの設定でデフォルトが定まっているので任せます。

      # compressionはbtrfsがバックエンドであることを考えると、
      # むしろ明示的に無効にしておいたほうがストレージ効率は良いですが、
      # ネットワーク通信のことを考えると有効にしておいたほうが良いかもしれません。
      # デフォルト値に任せます。

      # ガベージコレクションはデフォルトに近い緩めの値を設定しておきます。
      garbage-collection = {
        interval = "1 day";
        default-retention-period = "6 months";
      };
    };
  };
  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
  };
  users.groups.atticd = {
    members = [ username ];
  };
  systemd.tmpfiles.rules = [
    "d /mnt/noa/atticd 0755 atticd atticd -"
  ];
  # 管理トークン発行例。
  # ```
  # TOKEN="$(sudo atticd-atticadm make-token --sub 'seminar' --validity '4y' --pull 'private' --push 'private' --create-cache 'private')"
  # ```
  # 読み書きトークン発行例。
  # ```
  # TOKEN=$(sudo atticd-atticadm make-token --sub 'bullet' --validity '4y' --pull 'private' --push 'private')
  # ```
  # トークンを利用してログインする。
  # ```
  # attic login ncaq https://nix-cache.ncaq.net "$TOKEN"
  # ```
}
