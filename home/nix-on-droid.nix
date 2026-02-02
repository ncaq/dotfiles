_: {
  # nix-on-droidのデフォルト設定。
  # Android端末でコンフリクトしたファイルを処理するのには手間がかかるので合理的。
  environment.etcBackupExtension = ".bak";

  # Androidホストのタイムゾーンは自動的に引き継がれないようなので、
  # 明示的に設定。
  time.timeZone = "Asia/Tokyo";

  home-manager = {
    config = ./.;
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
  };
}
