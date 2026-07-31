/**
  systemdサービスへ共通で適用するハードニング設定。

  各サービスの`serviceConfig`へ`//`で先頭側にマージして、
  サービス固有の設定と差分だけを上書き側に書く。

  ```nix
  serviceConfig = hardening.network // {
    ExecStart = "...";
    ReadWritePaths = [ "/var/lib/foo" ];
  };
  ```

  設定を外す必要がある場合は`builtins.removeAttrs`で属性ごと外し、
  理由をコメントに残す。

  NixOSモジュールへは`flake.nix`の`specialArgs`経由で、
  `hardening`として配布される。
*/
let
  base = {
    # 空リストはNixOSモジュールがディレクティブごと省略してしまうため、
    # 空文字列でbounding setを空集合にリセットする。
    # capabilityが必要なサービスは必要なものだけのリストで上書きする。
    CapabilityBoundingSet = "";
    LockPersonality = true;
    MemoryDenyWriteExecute = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [ "@system-service" ];
  };
in
{
  # ソケットを一切使わないサービス向け。
  # あらゆるアドレスファミリを禁止して、
  # ネットワーク名前空間ごと隔離する。
  isolated = base // {
    PrivateNetwork = true;
    RestrictAddressFamilies = "none";
  };
  # UNIXソケットだけで通信するサービス向け。
  # ネットワーク名前空間ごと隔離する。
  unixSocket = base // {
    PrivateNetwork = true;
    RestrictAddressFamilies = [ "AF_UNIX" ];
  };
  # ネットワーク通信を行うサービス向け。
  network = base // {
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
  };
}
