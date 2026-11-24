{
  # ストアのGCと最適化の起動の流れは、パッケージの隣にある。
  # 負荷の検査と打ち切りのコマンドと対になっていて、パッケージのテストもそのユニットを動かすため。
  imports = [ ../../pkgs/nix-store-maintenance/module.nix ];
}
