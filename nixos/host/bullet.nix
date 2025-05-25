{ ... }:
{
  # ネイティブGNU/Linux環境のデスクトップPC。
  imports = [ ./bullet/disko-config.nix ];
  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
    grub = {
      enable = true;
      useOSProber = true;
      efiSupport = true;
      devices = [ "nodev" ];
      extraConfig = ''
        GRUB_CMDLINE_LINUX="rootflags=subvol=@"
      '';
    };
  };
}
