# microVMを動かすホスト側のユニットのハードニング。
#
# microVMの中ではCIのジョブのような外から来たプログラムを動かす。
# ゲストから見て攻撃面になるのは、
# 仮想デバイスを実装するVMM(cloud-hypervisor)と、ホストのディレクトリを見せるvirtiofsdで、
# どちらもホストの普通のプロセスとして動く。
# microvm.nixのユニットは専用ユーザで動かす他はほとんど絞っていないので、
# ゲストに抜けられた時に届く範囲を狭める。
#
# ここの設定はテンプレートのユニットへ足すので、全てのmicroVMに効く。
{ hardening, ... }:
{
  # VMMは専用ユーザの`microvm`で動く。
  # 自分のディレクトリへの書き込みと、KVMとTAPのデバイスの他は閉じる。
  systemd.services."microvm@".serviceConfig =
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
}
