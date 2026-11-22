/**
  `trash-empty-stray`がゴミ箱を探す起点を、`fileSystems`の定義から決める関数。

  型: AttrSet -> [String]

  ユーザのデータを置く場所を全て探す。
  `/efi`と`/home`と`/mnt`は常に起点にする。
  探索は起点と違うデバイスのディレクトリへは降りないので、
  `/mnt`の下にマウントするローカルのディスクは、起点として別に足す。

  以下は起点にしない。

  - ネットワークのファイルシステム。実体のあるホストの側で掃除する。
    `/mnt/chihiro`のようなCIFSのマウントは`systemd.mounts`で定義しているので、元から`fileSystems`に無い
  - `fuse.gocryptfs`のような、他のファイルシステムの中身を別の見え方で見せるもの
  - `/mnt`の下以外のマウント。ユーザのデータを置く場所ではない

  マウントしていない入れ子のbtrfsサブボリュームの直下に作られたゴミ箱は対象外になる。
  親と違うデバイスに見えるので降りず、マウントの定義も無いので起点にも入らない。

  # 引数

  - `lib`: 属性集合とリストの操作に使う
*/
{ lib }:
let
  localDiskTypes = [
    "btrfs"
    "exfat"
    "ext4"
    "vfat"
    "xfs"
  ];
  strayRoots =
    fileSystems:
    [
      "/efi"
      "/home"
      "/mnt"
    ]
    ++ lib.sort lib.lessThan (
      lib.mapAttrsToList (_: fileSystem: fileSystem.mountPoint) (
        lib.filterAttrs (
          _: fileSystem:
          lib.hasPrefix "/mnt/" fileSystem.mountPoint && lib.elem fileSystem.fsType localDiskTypes
        ) fileSystems
      )
    );

  # `fileSystems`と同じ形の入力を、マウントポイントと種類の組から作る。
  fileSystemsOf = lib.mapAttrs (mountPoint: fsType: { inherit mountPoint fsType; });
  always = [
    "/efi"
    "/home"
    "/mnt"
  ];
  show = lib.concatStringsSep " ";
in
assert lib.assertMsg (strayRoots { } == always) "マウントが無い時の起点が違います: ${show (strayRoots { })}";
assert lib.assertMsg (
  strayRoots (fileSystemsOf {
    "/mnt/x" = "btrfs";
  }) == always ++ [ "/mnt/x" ]
) "/mntの下のローカルのディスクが起点に入りません";
# ネットワークのファイルシステムと、他のファイルシステムを別の見え方で見せるものは入れない。
assert lib.assertMsg (
  strayRoots (fileSystemsOf {
    "/mnt/y" = "cifs";
    "/mnt/z" = "nfs4";
    "/mnt/x/backup" = "fuse.gocryptfs";
  }) == always
) "ローカルのディスクではないものが起点に入りました";
# /mntの下以外のマウントは入れない。`/mnt`で始まるだけの別の場所も入れない。
assert lib.assertMsg (
  strayRoots (fileSystemsOf {
    "/" = "btrfs";
    "/srv" = "ext4";
    "/mnt2" = "ext4";
  }) == always
) "/mntの下以外のマウントが起点に入りました";
# 属性の並びに関わらず、足した起点は名前の順になる。
assert lib.assertMsg (
  strayRoots (fileSystemsOf {
    "/mnt/b" = "ext4";
    "/mnt/a" = "xfs";
    "/mnt/c" = "exfat";
  }) == always
  ++ [
    "/mnt/a"
    "/mnt/b"
    "/mnt/c"
  ]
) "足した起点が名前の順になっていません";
strayRoots
