{ lib, ... }:
{
  # GitHub ActionsのランナーのVMについて、
  # ホスト側で用意するものの場所をモジュールの外から参照できるようにします。
  # ブートテストがこれを読んで、
  # ストアの準備(`test/nixos-boot/script/github-runner-store.nix`)と、
  # GCの前後の処理(`test/nixos-boot/script/github-runner-gc.nix`)を確かめます。
  # 値は`github-runner-x64.nix`が定義します。
  options.local.githubRunnerVms = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          storeService = lib.mkOption {
            type = lib.types.str;
            description = "Host service that prepares the Nix store for the runner VM";
          };
          storeDatabase = lib.mkOption {
            type = lib.types.path;
            description = "Copy of the host Nix database handed to the runner VM";
          };
          overlayImage = lib.mkOption {
            type = lib.types.path;
            description = "Image of the writable store layer of the runner VM";
          };
        };
      }
    );
    default = { };
    description = "Host-side resources of GitHub Actions runner VMs, keyed by VM name";
  };
}
