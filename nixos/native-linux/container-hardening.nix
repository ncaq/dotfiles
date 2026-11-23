/**
  NixOS Containerを動かすホスト側のユニット(`container@<name>`)のハードニング。

  ユニットのプロセスはホストのrootで動くsystemd-nspawnで、
  コンテナの中の全てのプロセスはその子孫になる。
  seccompのフィルタと`NoNewPrivileges`は子孫へ引き継がれて外せないので、
  ここへ書いた制限はnspawnだけでなく、コンテナの中身にも効く。

  nspawnは自分でもコンテナの中身にseccompのフィルタとcapabilityの制限を掛ける。
  ここではnspawnが掛けないものを足す。
  特にアドレスファミリとシステムコールのABIはnspawnが絞らないので、
  コンテナの中から届くカーネルの攻撃面がその分だけ残っている。
  `privateUsers = "identity"`のコンテナは中のrootがホストのrootと同じUIDなので、
  カーネルの脆弱性がそのままホストの権限に繋がる。

  nspawnはコンテナを作るために名前空間もマウントも強い権限も使うので、
  `hardening.network`の多くは適用できない。
  外すものはそれぞれ理由を下に書く。
  「実測」と書いたものは、その設定だけを足したコンテナをVMで起動して確かめた結果。
  `systemd-analyze security`の評価が高くならないのは、その結果になる。

  個々のコンテナで外す必要が出た時は、
  `systemd.services."container@<name>".serviceConfig`を`lib.mkForce`で上書きする。
*/
{
  lib,
  config,
  hardening,
  ...
}:
let
  serviceConfig =
    removeAttrs hardening.network [
      # nspawnがコンテナを作るのに`CAP_SYS_ADMIN`を始めとする多くのcapabilityを使う。
      # コンテナの中へ渡すものはnspawnが自分で絞る。
      "CapabilityBoundingSet"
      # 実測では、コンテナの中のjournaldやlogindが起動に失敗する。
      "LockPersonality"
      # コンテナの中で動くものにはJITを使うものがある。
      "MemoryDenyWriteExecute"
      # 実測では、nspawnが`clone`に失敗してコンテナが起動しない。
      "RestrictNamespaces"
      # 実測では、コンテナの中のNixOSがsetuidのラッパを作れない。
      "RestrictSUIDSGID"
      # 実測では、nspawnがコンテナのホスト名を設定できない。
      "ProtectHostname"
      # 以下はユニットに専用のマウント名前空間を持たせるもの。
      # 実測では、どれか1つを掛けるだけで、
      # `ephemeral`なコンテナのルートの複製が`Too many open files`で失敗して起動しない。
      # 他に何も掛けない`PrivateMounts`だけでも同じなので、
      # 個々の設定の中身ではなく、マウント名前空間を持つこと自体が原因になる。
      #
      # `ephemeral`ではないコンテナでも、
      # `PrivateDevices`はnspawnがコンテナの`/dev`にデバイスノードを作れず、
      # `ProtectControlGroups`はnspawnがコンテナのcgroupを作れず、
      # `ProtectSystem`もコンテナが起動しない。
      #
      # 失うものは小さい。
      # デバイスはnixpkgsのモジュールが`DevicePolicy=closed`で既に閉じている。
      # カーネルのログとモジュールは、
      # nspawnがコンテナへ`CAP_SYSLOG`と`CAP_SYS_MODULE`を渡さないことで既に塞がっていて、
      # モジュールを操作するシステムコールは下の`SystemCallFilter`でも禁止する。
      # 残りはホストのファイルを隠すもので、コンテナの中からは元からホストのファイルが見えない。
      "PrivateDevices"
      "PrivateTmp"
      "ProtectControlGroups"
      "ProtectHome"
      "ProtectKernelLogs"
      "ProtectKernelModules"
      "ProtectKernelTunables"
      "ProtectSystem"
    ]
    // {
      RestrictAddressFamilies = hardening.network.RestrictAddressFamilies ++ [
        # nspawnがvethを作り、コンテナの中の`ip`やsystemdがネットワークを設定する。
        "AF_NETLINK"
      ];
      # 許可するものを並べるとnspawnとコンテナの中の全てのプロセスの分を拾い切れないので、
      # コンテナでは使わない種類だけを禁止する。
      #
      # `@reboot`は禁止しない。実測では、禁止するとコンテナが起動しない。
      # コンテナの中のsystemdが使うのは`reboot`だけなので、
      # 同じ`@reboot`に入っているkexecは個別に禁止する。
      # `@debug`は禁止しない。コンテナの中で`strace`や`gdb`を使えるようにしておく。
      # `@clock`は`hardening.network`から残る`ProtectClock`も同じものを禁止するので重複している。
      # `systemd-analyze security`は`SystemCallFilter`に書いたものしか数えず、
      # 外すと守りは同じまま評価だけが7.5から7.7へ悪くなるので、ここにも書いておく。
      SystemCallFilter = [
        "~@clock"
        "~@cpu-emulation"
        "~@module"
        "~@obsolete"
        "~@raw-io"
        "~@swap"
        "~kexec_file_load"
        "~kexec_load"
      ];
    };
in
{
  systemd.services = lib.mapAttrs' (
    name: _: lib.nameValuePair "container@${name}" { inherit serviceConfig; }
  ) config.containers;
}
