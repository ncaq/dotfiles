{ lib, ... }:
{
  # GitHub ActionsのランナのVMについて、
  # ホスト側で用意するものの名前をモジュールの外から参照できるようにします。
  # ブートテストがこれを読んで、
  # VMの再起動(`test/nixos-boot/script/github-runner-restart.nix`)と、
  # GCとストアの最適化の前後の処理(`test/nixos-boot/script/github-runner-gc.nix`)を確かめます。
  # Mackerelのチェック(`nixos/host/seminar/mackerel.nix`)は、
  # これを読んでランナがGitHubに登録されているかを確かめます。
  # 値は`github-runner-x64.nix`が定義します。
  options.local.githubRunnerVms = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          storeService = lib.mkOption {
            type = lib.types.str;
            description = "Host service that prepares the Nix store for the runner VM";
          };
          repository = lib.mkOption {
            type = lib.types.str;
            description = "GitHub repository the runners of the VM belong to, as OWNER/REPO";
          };
          runnerNames = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Names under which the runners of the VM register on GitHub";
          };
        };
      }
    );
    default = { };
    description = "Host-side resources of GitHub Actions runner VMs, keyed by VM name";
  };
}
