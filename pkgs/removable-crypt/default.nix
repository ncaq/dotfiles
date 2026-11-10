# 暗号化されたリムーバブルデバイス1台をマウントする`mnt-<名前>`と、
# アンマウントする`umnt-<名前>`を提供します。
# `lib/removable-crypt.nix`がデバイスごとに呼びます。
# 何をするかは`mount.bash`と`unmount.bash`の冒頭に書いてあります。
{
  lib,
  runCommand,
  makeWrapper,
  shellcheck,
  btrfs-progs,
  coreutils,
  snapper,
  systemd,
  util-linux,
  # マッパーの名前。マウントポイントは`/mnt/<name>`になります。
  name,
  # `/dev/disk/by-id/`以下のデバイスのID。
  deviceId,
  # 全てのファイルシステムで使うマウントオプション。
  mountOptions,
  # btrfsの時に`mountOptions`へ足すマウントオプション。
  btrfsMountOptions,
}:
let
  runtimePath = lib.makeBinPath [
    btrfs-progs
    coreutils
    snapper
    systemd
    util-linux
  ];
in
runCommand "removable-crypt-${name}"
  {
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
    meta.mainProgram = "mnt-${name}";
  }
  ''
    shellcheck ${./mount.bash} ${./unmount.bash}
    install -Dm755 ${./mount.bash} $out/libexec/removable-crypt/mount.bash
    install -Dm755 ${./unmount.bash} $out/libexec/removable-crypt/unmount.bash
    patchShebangs $out/libexec
    # sudo越しに呼ぶコマンドなので、呼び出し元の環境変数で上書きできない`--set`で固定します。
    makeWrapper $out/libexec/removable-crypt/mount.bash $out/bin/${lib.escapeShellArg "mnt-${name}"} \
      --set REMOVABLE_CRYPT_NAME ${lib.escapeShellArg name} \
      --set REMOVABLE_CRYPT_DEVICE_ID ${lib.escapeShellArg deviceId} \
      --set REMOVABLE_CRYPT_MOUNT_OPTIONS ${lib.escapeShellArg (lib.concatStringsSep "," mountOptions)} \
      --set REMOVABLE_CRYPT_BTRFS_MOUNT_OPTIONS ${
        lib.escapeShellArg (lib.concatStringsSep "," (mountOptions ++ btrfsMountOptions))
      } \
      --prefix PATH : ${runtimePath}
    makeWrapper $out/libexec/removable-crypt/unmount.bash $out/bin/${lib.escapeShellArg "umnt-${name}"} \
      --set REMOVABLE_CRYPT_NAME ${lib.escapeShellArg name} \
      --prefix PATH : ${runtimePath}
  ''
