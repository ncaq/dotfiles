_: {
  # nixpkgsのメンテナンスでaarch64-linux向けのビルドやテストを手元で行うため、
  # qemuのuser levelエミュレーションを登録します。
  # `nix.settings.extra-platforms`にも自動で追加されます。
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
}
