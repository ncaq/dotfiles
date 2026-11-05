{
  boot = {
    loader = {
      limine = {
        secureBoot = {
          autoEnrollKeys = {
            # seminarはデュアルブートしていないので、
            # Microsoftの鍵を登録する必要はありません。
            extraArgs = [ "--firmware-builtin" ];
          };
        };
      };
    };
    initrd = {
      # LUKSの復号はTPM2に任せて、ヘッドレスのまま再起動できるようにしている。
      # 登録はPCR7(Secure Bootの状態)だけに縛っていて、
      # カーネルやinitrdの計測(PCR11など)は含めていない。
      # そのため暗号化されていない/efiの中身を差し替えられる物理アクセスには、
      # Secure Bootが止めない限り耐えられない。
      #
      # 自宅サーバの脅威モデルとして、
      # 物理アクセスされる(レンチで殴られる)攻撃は諦めている。
      # 守りたいのは、ディスクを抜かれたり廃棄したりした時に中身が読めないことまで。
      # `/mnt/noa`のLUKS(`disk.nix`)も同じ方針。
      luks.devices = {
        nixos-root = {
          device = "/dev/disk/by-partlabel/disk-main-nixos-root";
          allowDiscards = true;
          crypttabExtraOpts = [
            "tpm2-device=auto"
          ];
        };
      };
    };
  };
}
