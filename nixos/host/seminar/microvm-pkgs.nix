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
# コンテナの分は`nixos/native-linux/container-template.nix`です。
# 別のファイルにしているのは、
# `microvm.vms`のオプションがmicroVMのホストモジュールを取り込んだホストにしか無いためです。
{ lib, config, ... }:
let
  # ハイパーバイザが`stratovirt`のmicroVMの名前。
  stratovirtVms = lib.attrNames (
    lib.filterAttrs (_: vm: vm.config.config.microvm.hypervisor == "stratovirt") config.microvm.vms
  );
in
{
  # overlayを空にして良い前提が崩れたら評価を止めます。
  config.assertions = [
    {
      assertion = stratovirtVms == [ ];
      message = ''
        ハイパーバイザが`stratovirt`のmicroVMがあります: ${lib.concatStringsSep ", " stratovirtVms}
        `nixos/host/seminar/microvm-pkgs.nix`がmicrovm.nixの`stratovirt`用のoverlayを消しているので、見直してください。
      '';
    }
  ];

  options.microvm.vms = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.config.nixpkgs.overlays = lib.mkForce [ ];
      }
    );
  };
}
