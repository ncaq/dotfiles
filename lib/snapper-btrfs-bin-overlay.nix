/**
  snapperの`snbk`(snapper-backup)が、btrfs CLIを`/usr/sbin/btrfs`という、
  NixOSには存在しない絶対パスで起動してしまう問題を修正するoverlay。

  `snapper`本体はサブボリューム操作を`libbtrfsutil`(C関数)で行うためCLIを起動しないが、
  `snbk`はbtrfs send/receiveのprobeや転送で`BTRFS_BIN`定数のCLIを起動する。
  この`BTRFS_BIN`は`configure.ac`の、
  `AC_PATH_PROG([BTRFS_BIN], [btrfs], [/usr/sbin/btrfs])`で決まる。
  configure時にPATHから`btrfs`を探し、見つからなければ`/usr/sbin/btrfs`をフォールバックする。

  nixpkgsのsnapperは`strictDeps = true`かつ`btrfs-progs`が`buildInputs`にしか無いため、
  configure時のPATHに`btrfs`が現れず、フォールバックの`/usr/sbin/btrfs`が埋め込まれてしまう。
  結果としてsnapper-backup.serviceが毎回exit 127 (not found)で失敗する。

  `AC_PATH_PROG`は変数が事前設定済みならPATH探索をスキップするので、
  `BTRFS_BIN`をconfigure引数で明示し、btrfs-progsのstoreパスを直接埋め込む。

  upstreamのnixpkgsでも修正されるべきパッケージングバグ。
*/
_final: prev: {
  snapper = prev.snapper.overrideAttrs (old: {
    configureFlags = (old.configureFlags or [ ]) ++ [
      "BTRFS_BIN=${prev.btrfs-progs}/bin/btrfs"
    ];
  });
}
