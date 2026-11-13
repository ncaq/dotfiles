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

  コマンドにしているのは、
  コンテナとmicroVMでログの入る場所が違っても、
  マシンの名前だけで読めるようにするため。

  - コンテナ: 既定のjournalの`container@<名前>.service`。`journalctl --unit`で読む
  - microVM: マシンと同じ名前のjournalのnamespace。`journalctl --namespace`で読む

  microVMの中の設定は、
  microVMのホストモジュールを取り込んだホストにしかオプションが無いので、
  そのホストの設定(`nixos/host/seminar/microvm-log.nix`)に置いている。

  # microVMのログはjournalのnamespaceへ分ける

  ゲストが書く量はゲストが決められる。
  journaldは上限に達すると古いファイルから消すので、
  既定のjournalへ入れると、
  大量に書くゲストがホスト自身のログ(sshdやsudoの記録を含む)を押し出せる。
  CIのランナーのmicroVMでは持ち込まれたコードがrootで動くので、
  これはホストの証跡を消す手段になる。
  レート制限は量を減らすだけで、
  保存先を共有している限り押し出せることは変わらない。

  namespaceはjournaldのインスタンスも保存先も上限も別なので、
  ゲストがどれだけ書いても消えるのはそのゲスト自身の古いログだけになる。
  VMごとに分けているのは、
  あるVMが他のVMのログを押し出すことも防ぐため。

  # コンテナのログは分けていない

  コンテナにも同じ`LogNamespace`を付けると、コンテナが起動しなくなる。
  systemdはnamespaceのソケットを見せるためにサービスをマウント名前空間へ入れるが、
  その中ではnspawnの`--ephemeral`が、
  `Failed to create ephemeral snapshot: Too many open files`で失敗する。
  ブートテストのpostgresqlのコンテナで確かめた。

  コンテナの中で動くのは自分で選んで入れたサービスで、
  持ち込まれたコードがrootで動くmicroVMとは前提が違う。
  コンテナが大量に書けばホストの古いログは押し出されうるが、
  それは受け入れている。
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

  # マシンの名前から、そのログを選ぶjournalctlの引数への対応。
  selectors =
    lib.genAttrs containerNames (name: "--unit=container@${name}.service")
    // lib.genAttrs vmNames (name: "--namespace=${name}");

  # namespaceごとのjournalの上限。
  # 何も書かないとnamespaceごとにファイルシステムの10%(最大4G)まで使う。
  maxUse = "1G";

  machineLog = pkgs.writeShellApplication {
    name = "machine-log";
    runtimeInputs = [ config.systemd.package ];
    text = ''
      machines=(${lib.escapeShellArgs (lib.attrNames selectors)})

      if [[ $# -eq 0 ]]; then
        printf '%s\n' "''${machines[@]}"
        exit 0
      fi

      name=$1
      shift

      case "$name" in
      ${lib.concatStrings (
        lib.mapAttrsToList (name: selector: ''
          ${lib.escapeShellArg name}) selector=${lib.escapeShellArg selector} ;;
        '') selectors
      )}
      *)
        echo "machine-log: unknown machine: $name" >&2
        echo "machines:" >&2
        printf '  %s\n' "''${machines[@]}" >&2
        exit 1
        ;;
      esac

      exec journalctl "$selector" "$@"
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

  config = lib.mkIf (selectors != { }) {
    environment.systemPackages = [ machineLog ];

    systemd.services = lib.genAttrs' vmNames (
      name:
      lib.nameValuePair "microvm@${name}" {
        # `microvm@`はテンプレートなので、このVMの分だけを追加の設定として重ねる。
        overrideStrategy = "asDropin";
        serviceConfig.LogNamespace = name;
      }
    );

    environment.etc = lib.genAttrs' vmNames (
      name:
      lib.nameValuePair "systemd/journald@${name}.conf" {
        text = ''
          [Journal]
          Storage=persistent
          SystemMaxUse=${maxUse}
        '';
      }
    );

    assertions = [
      {
        assertion = duplicated == [ ];
        message = "machine-log: コンテナとmicroVMで名前が重なっているので、名前からログの場所を決められません: ${lib.concatStringsSep ", " duplicated}";
      }
    ];
  };
}
