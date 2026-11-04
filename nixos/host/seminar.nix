{ lib, inputs, ... }:
{
  imports = with inputs; [
    nixos-hardware.nixosModules.common-cpu-amd
    nixos-hardware.nixosModules.common-cpu-amd-pstate
    nixos-hardware.nixosModules.common-gpu-amd
    nixos-hardware.nixosModules.common-pc
    nixos-hardware.nixosModules.common-pc-ssd

    microvm.nixosModules.host

    # サーバだがGUIを含む`native-linux`層を他のクライアントと同じように取り込む。
    # 層を分けない単純さもあるが、
    # リモートデスクトップや自動化でGUIを使う可能性を残すために、
    # あえて他のクライアントと同じ構成にしている。
    # 閉包にデスクトップアプリが入るのは承知の上なので、
    # サーバに不要だからという理由で外さないこと。
    ../native-linux

    ../server

    ../ollama

    ./seminar
  ];
  local.cpuTarget = "AMD Ryzen 5 7600 6-Core Processor";
  # GUIをデフォルトでは起動しない。
  systemd.defaultUnit = lib.mkForce "multi-user.target";
}
