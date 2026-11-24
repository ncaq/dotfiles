# コンテナとmicroVMの中のログを、マシンの名前だけで読むコマンド。
#
# `nixos/native-linux/machine-log.nix`が、そのホストのマシンの一覧を`override`で渡して入れる。
# なぜコマンドにしているかと、ログがどこへ入るかは、そちらの冒頭に書いてある。
#
# ```console
# machine-log                    # マシンの一覧
# machine-log forgejo            # forgejoのコンテナのログ
# machine-log mcp-nixos -f       # 引数はjournalctlへそのまま渡る
# ```
#
# 名前を引いて`journalctl`へ渡すだけなので、シェルスクリプトにしています。
{
  lib,
  runCommand,
  systemd,
  writeShellApplication,
  writeShellScriptBin,
  # マシンの名前から、そのログを選ぶ`journalctl`の引数への対応。
  selectors ? { },
}:
let
  mkMachineLog =
    {
      selectors,
      # `journalctl`を持つパッケージ。
      journal,
    }:
    writeShellApplication {
      name = "machine-log";
      runtimeInputs = [ journal ];
      text = ''
        # 連想配列は取り出す順序が決まらないので、一覧に出す名前は別に並べて持ちます。
        machines=(${lib.escapeShellArgs (lib.attrNames selectors)})
        declare -A selectors=(
        ${lib.concatStrings (
          lib.mapAttrsToList (name: selector: ''
            [${lib.escapeShellArg name}]=${lib.escapeShellArg selector}
          '') selectors
        )}
        )

        if [[ $# -eq 0 ]]; then
          printf '%s\n' "''${machines[@]}"
          exit 0
        fi

        name=$1
        shift

        if [[ -z ''${selectors[$name]+known} ]]; then
          echo "machine-log: unknown machine: $name" >&2
          echo "machines:" >&2
          printf '  %s\n' "''${machines[@]}" >&2
          exit 1
        fi

        exec journalctl "''${selectors[$name]}" "$@"
      '';
    };

  # 名前の対応はNixの評価時にシェルの連想配列として生成しているので、
  # 生成の仕方が崩れると全ての名前が知らない名前の側へ落ちます。
  # 渡された引数をそのまま出す代わりの`journalctl`で、分岐ごとの振る舞いを確かめます。
  # 中のログが実際にホストへ届くことは、ホストをブートするテストで見ています。
  commandTest =
    let
      machineLog = mkMachineLog {
        selectors = {
          forgejo = "--unit=container@forgejo.service";
          mcp-nixos = "--namespace=mcp-nixos";
        };
        journal = writeShellScriptBin "journalctl" ''
          printf '%s\n' "$@"
        '';
      };
    in
    runCommand "machine-log-command-test" { nativeBuildInputs = [ machineLog ]; } ''
      expect() {
        if [ "$1" != "$2" ]; then
          echo "expected: $1" >&2
          echo "actual: $2" >&2
          exit 1
        fi
      }

      # 引数無しはマシンの一覧を1行ずつ出す。
      expect "forgejo
      mcp-nixos" "$(machine-log)"

      # コンテナはユニットで、microVMはjournalのnamespaceで選ぶ。
      expect "--unit=container@forgejo.service" "$(machine-log forgejo)"
      expect "--namespace=mcp-nixos" "$(machine-log mcp-nixos)"

      # マシンの名前より後ろの引数は、選ぶ引数の後ろへそのまま渡る。
      expect "--unit=container@forgejo.service
      -b
      --grep=two words" "$(machine-log forgejo -b '--grep=two words')"

      # 知らない名前は、`journalctl`を呼ばずに失敗して、一覧を案内する。
      if unknown=$(machine-log no-such-machine 2>&1); then
        echo "unknown machine succeeded: $unknown" >&2
        exit 1
      fi
      expect "machine-log: unknown machine: no-such-machine
      machines:
        forgejo
        mcp-nixos" "$unknown"

      touch "$out"
    '';
in
(mkMachineLog {
  inherit selectors;
  journal = systemd;
}).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      tests.command = commandTest;
    };
  })
