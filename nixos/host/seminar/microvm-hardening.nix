# microVMを動かすホスト側のユニットのハードニング。
#
# microVMの中ではCIのジョブのような外から来たプログラムを動かす。
# ゲストから見て攻撃面になるのは、
# 仮想デバイスを実装するVMM(cloud-hypervisor)と、ホストのディレクトリを見せるvirtiofsdで、
# どちらもホストの普通のプロセスとして動く。
# microvm.nixのユニットは専用ユーザで動かす他はほとんど絞っていないので、
# ゲストに抜けられた時に届く範囲を狭める。
#
# テンプレートのユニットへ足すので、全てのmicroVMに効く。
{
  lib,
  config,
  hardening,
  ...
}:
let
  # 書き込みで共有しているディレクトリ。
  writableShareSources =
    vm:
    map (share: share.source) (
      lib.filter (share: share.proto == "virtiofs" && !share.readOnly) vm.config.config.microvm.shares
    );
in
{
  systemd.services = {
    # VMMは専用ユーザの`microvm`で動く。
    # 自分のディレクトリへの書き込みと、KVMとTAPのデバイスの他は閉じる。
    "microvm@".serviceConfig =
      removeAttrs hardening.network [
        # KVMとTAPのデバイスが要るので、下の`DeviceAllow`で個別に開ける。
        "PrivateDevices"
      ]
      // {
        DevicePolicy = "closed";
        DeviceAllow = [
          "/dev/kvm rw"
          # 用意済みのTAPへ繋ぐ。
          "/dev/net/tun rw"
        ];
        # ソケットとディスクのイメージを置く作業ディレクトリ。
        ReadWritePaths = [ "/var/lib/microvms/%i" ];
        SystemCallFilter = hardening.network.SystemCallFilter ++ [
          # cloud-hypervisorは起動時に自分でもseccompのフィルタを掛ける。
          "@sandbox"
        ];
        # 他のプロセスの情報を`/proc`から読めなくする。
        ProtectProc = "invisible";
      };

    # virtiofsdはホストのrootで動いて、ゲストからの要求の通りにホストのファイルを操作する。
    # 自分でも名前空間へ入ってから要求を受けるが、
    # その準備が終わるまでと、まとめて起動するsupervisordは、ホストがそのまま見えている。
    # 共有するディレクトリと作業ディレクトリの他へは書けないようにして、権限も要るものへ絞る。
    # 通信はファイルシステムの上のUNIXソケットだけなので、ネットワークも閉じる。
    "microvm-virtiofsd@".serviceConfig =
      removeAttrs hardening.unixSocket [
        # `CAP_MKNOD`も落とす。
        # virtiofsdは起動時に持っておくcapabilityを自分で設定するので、
        # 既定で持つものがbounding setに無いと起動に失敗する。
        # デバイスは下の`DevicePolicy`で閉じる。
        "PrivateDevices"
        # microvm.nixが既に`yes`と書いていて、同じ意味の`true`を足すと定義が衝突する。
        "PrivateTmp"
      ]
      // {
        CapabilityBoundingSet = [
          # 名前空間を作って、共有するディレクトリをルートにする。
          "CAP_SYS_ADMIN"
          # 持っておくcapabilityを自分で減らす。
          "CAP_SETPCAP"
          # ゲストの代わりにファイルを操作するために、virtiofsdが既定で持っておくもの。
          "CAP_CHOWN"
          "CAP_DAC_OVERRIDE"
          "CAP_FOWNER"
          "CAP_FSETID"
          "CAP_MKNOD"
          "CAP_SETFCAP"
          "CAP_SETGID"
          "CAP_SETUID"
          # ファイルハンドルからファイルを開く。
          "CAP_DAC_READ_SEARCH"
        ];
        # 標準の疑似デバイスの他は開けない。デバイスノードを作ることもできなくなる。
        DevicePolicy = "closed";
        # virtiofsdが自分で入るのに使う種類だけを許す。
        RestrictNamespaces = [
          "mnt"
          "net"
          "pid"
        ];
        # 許可するものを並べると名前空間の準備に使うものを拾い切れないので、
        # ファイルの共有では使わない種類だけを禁止する。
        SystemCallFilter = [
          "~@clock"
          "~@cpu-emulation"
          "~@debug"
          "~@module"
          "~@obsolete"
          "~@raw-io"
          "~@reboot"
          "~@swap"
        ];
        # ソケットとsupervisordのログを置く作業ディレクトリ。
        # 書き込みで共有するディレクトリは、下でVMごとに足す。
        ReadWritePaths = [ "/var/lib/microvms/%i" ];
      };
  }
  // lib.mapAttrs' (
    name: vm:
    lib.nameValuePair "microvm-virtiofsd@${name}" {
      overrideStrategy = "asDropin";
      serviceConfig.ReadWritePaths = writableShareSources vm;
    }
  ) config.microvm.vms;
}
