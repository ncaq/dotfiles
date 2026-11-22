{
  lib,
  config,
  ...
}:
let
  # 探して見つけるゴミ箱の起点。
  #
  # ユーザのデータを置く場所を全て探す。
  # 起点と違うデバイスのディレクトリへは降りないので、
  # /mntの下にマウントするローカルのディスクは起点として別に渡す。
  # ネットワークマウントは実体のあるホストの側で掃除するので、ここへは入れない。
  # `/mnt/chihiro`のようなCIFSのマウントは`systemd.mounts`で定義しているので、元から`fileSystems`に無い。
  #
  # マウントしていない入れ子のbtrfsサブボリュームの直下に作られたゴミ箱は対象外になる。
  # 親と違うデバイスに見えるので降りず、マウントの定義も無いので起点にも入らない。
  localDiskTypes = [
    "btrfs"
    "exfat"
    "ext4"
    "vfat"
    "xfs"
  ];
  strayRoots = [
    "/efi"
    "/home"
    "/mnt"
  ]
  ++ lib.sort lib.lessThan (
    lib.mapAttrsToList (_: fileSystem: fileSystem.mountPoint) (
      lib.filterAttrs (
        _: fileSystem:
        lib.hasPrefix "/mnt/" fileSystem.mountPoint && lib.elem fileSystem.fsType localDiskTypes
      ) config.fileSystems
    )
  );
in
{
  # ユニットの定義はパッケージの隣にある。
  # 権限の絞り込みがコマンドの動きと対になっていて、パッケージのテストもそのユニットを動かすため。
  imports = [ ../../pkgs/trash-empty-stray/module.nix ];

  options.local.trash.retentionDays = lib.mkOption {
    type = lib.types.ints.positive;
    default = 7;
    description = ''
      ゴミ箱へ入れてからこの日数が経ったものを消す。
      Sambaのゴミ箱のように別の仕組みで掃除するものも、保持期間が食い違わないようにここを参照する。
    '';
  };

  config.services.trash-empty = {
    enable = true;
    inherit (config.local.trash) retentionDays;
    stray.roots = strayRoots;
  };
}
