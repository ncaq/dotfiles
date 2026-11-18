# 全てのmicroVMの中の`pkgs`を、ホストの`pkgs`と同じインスタンスにします。
#
# microvm.nixは既定でホストの`pkgs`をmicroVMへ渡しますが、
# ゲスト用のモジュールが`stratovirt`からgtk3を外すoverlayを`nixpkgs.overlays`へ無条件に足します。
# overlayが1つでもあるとNixOSは`pkgs.appendOverlays`で新しいnixpkgsのインスタンスを作るので、
# microVMごとにパッケージのderivationを評価し直すことになります。
# `nix-eval-jobs`のワーカは評価中にGCをしないので、その分がそのままメモリの使用量に積み上がります。
#
# ここのmicroVMのハイパーバイザは全てcloud-hypervisorで`stratovirt`を使わないので、
# overlayを空にして同じインスタンスのまま使わせます。
# 3つのmicroVMのtoplevelの評価が確保する量は、これで約23%減りました。
#
# `mkForce`なので、microVMの中で足したoverlayも消えます。
# microVMにoverlayが必要になったら、ここを見直してください。
#
# 上流がoverlayを`stratovirt`の時だけ足すようになれば、このファイルは要らなくなります。
# https://github.com/ncaq/dotfiles/issues/1759
#
# コンテナの分は`nixos/core/container-pkgs.nix`です。
# 別のファイルにしているのは、
# `microvm.vms`のオプションがmicroVMのホストモジュールを取り込んだホストにしか無いためです。
{ lib, ... }:
{
  options.microvm.vms = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.config.nixpkgs.overlays = lib.mkForce [ ];
      }
    );
  };
}
