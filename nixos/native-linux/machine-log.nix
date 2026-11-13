/**
  コンテナとmicroVMの中のログを、ホストから同じコマンドで読めるようにする。

  全てのコンテナの中のjournalをコンソールへ流して(理由は`lib/journal-to-console.nix`)、
  ホストのjournalに入ったものを読む`machine-log`コマンドを提供する。

  ```console
  machine-log                    # マシンの一覧
  machine-log forgejo            # forgejoのコンテナのログ
  machine-log mcp-nixos -f       # 引数はjournalctlへそのまま渡る
  machine-log garage -b --grep=error
  ```

  コンテナは`container@<名前>.service`、
  microVMは`microvm@<名前>.service`のログとして入っているので、
  `journalctl --unit`で直接読んでも同じものが出る。
  コマンドにしているのは、
  どちらの仕組みで動いているマシンかを覚えていなくても名前だけで読めるようにするため。

  microVMの側の設定は、
  microVMのホストモジュールを取り込んだホストにしかオプションが無いので、
  そのホストの設定(`nixos/host/seminar/microvm-log.nix`)に置いている。
*/
{
  lib,
  config,
  pkgs,
  ...
}:
let
  containerNames = lib.attrNames config.containers;
  # microVMのホストモジュールを取り込んでいないホストでは`config.microvm`自体が無い。
  vmNames = lib.attrNames (config.microvm.vms or { });
  duplicated = lib.intersectLists containerNames vmNames;

  units =
    lib.genAttrs containerNames (name: "container@${name}.service")
    // lib.genAttrs vmNames (name: "microvm@${name}.service");

  machineLog = pkgs.writeShellApplication {
    name = "machine-log";
    runtimeInputs = [ config.systemd.package ];
    text = ''
      machines=(${lib.escapeShellArgs (lib.attrNames units)})

      if [[ $# -eq 0 ]]; then
        printf '%s\n' "''${machines[@]}"
        exit 0
      fi

      name=$1
      shift

      case "$name" in
      ${lib.concatStrings (
        lib.mapAttrsToList (name: unit: ''
          ${lib.escapeShellArg name}) unit=${lib.escapeShellArg unit} ;;
        '') units
      )}
      *)
        echo "machine-log: unknown machine: $name" >&2
        echo "machines:" >&2
        printf '  %s\n' "''${machines[@]}" >&2
        exit 1
        ;;
      esac

      exec journalctl --unit="$unit" "$@"
    '';
  };
in
{
  options.containers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        config.config = import ../../lib/journal-to-console.nix;
      }
    );
  };

  config = lib.mkIf (units != { }) {
    environment.systemPackages = [ machineLog ];

    assertions = [
      {
        assertion = duplicated == [ ];
        message = "machine-log: コンテナとmicroVMで名前が重なっているので、名前からユニットを決められません: ${lib.concatStringsSep ", " duplicated}";
      }
    ];
  };
}
