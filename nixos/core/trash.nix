{
  pkgs,
  lib,
  config,
  hardening,
  ...
}:
let
  days = config.local.trash.retentionDays;
  trashHardening =
    # 全ユーザのホーム、全マウント先、ホストの/tmpにあるゴミ箱を掃除するため、
    # それらを不可視またはread-onlyにする隔離は適用できない。
    removeAttrs hardening.isolated [
      "PrivateTmp"
      "ProtectHome"
      "ProtectSystem"
    ]
    // {
      # rootが他ユーザ所有のゴミ箱を走査・削除するために必要な権限だけを残す。
      CapabilityBoundingSet = [
        "CAP_DAC_OVERRIDE"
        "CAP_FOWNER"
      ];
    };
  # `trash-empty --all-users`が見つけられないゴミ箱を探して掃除する。
  #
  # `trash-put`は`os.path.ismount`で親を辿ってボリュームを決めるが、
  # `trash-empty`はマウントの一覧にある決まった種類のファイルシステムの直下しか見ない。
  # そのため以下のような場所に作られた`.Trash-<uid>`は掃除されずに残る。
  #
  # - CIFS越しに捨てた時に共有の中へ作られたもの。
  #   クライアントからはCIFSが対象外で、サーバからは共有のルートがマウントの直下ではない。
  # - マウントしていない入れ子のbtrfsサブボリュームの直下に作られたもの。
  #
  # 置き場所を列挙する代わりに、ユーザのデータを置く場所を全て探す。
  # `--one-file-system`を付けるので、
  # ネットワークマウントやスナップショットのサブボリュームへは降りない。
  # /mntの下にマウントしたローカルのファイルシステムは、起点として別に渡す。
  emptyStrayTrash = pkgs.writeShellApplication {
    name = "trash-empty-stray";
    runtimeInputs = with pkgs; [
      coreutils
      fd
      trash-cli
    ];
    text = ''
      roots=()
      for dir in /efi /home /mnt; do
        if [[ -d $dir ]]; then
          roots+=("$dir")
        fi
      done
      while IFS= read -r target; do
        if [[ $target == /mnt/* ]]; then
          roots+=("$target")
        fi
      done < <(df --local --output=target)

      # ディレクトリが無いか、空で消せた時に成功する。
      # 空でない時は何もせずに失敗する。
      remove_if_empty() {
        if [[ -e $1 ]]; then
          rmdir --ignore-fail-on-non-empty "$1"
        fi
        [[ ! -e $1 ]]
      }

      mapfile -d "" -t trash_dirs < <(
        fd --hidden --no-ignore --one-file-system --type d --prune --print0 '^\.Trash-[0-9]+$' "''${roots[@]}"
      )
      for trash_dir in "''${trash_dirs[@]}"; do
        trash-empty -f ${toString days} --trash-dir "$trash_dir"
        # 空になったゴミ箱は、ゴミ箱ごと消す。
        # うっかり作られた場所に空のディレクトリが残り続けて、手で消して回ることになるため。
        # 捨てている最中のゴミ箱を壊さないように、
        # `.trashinfo`が先に書かれる`info`が空の時だけ`files`へ進む。
        if remove_if_empty "$trash_dir/info" && remove_if_empty "$trash_dir/files"; then
          remove_if_empty "$trash_dir" || true
        fi
      done
    '';
  };
in
{
  options.local.trash.retentionDays = lib.mkOption {
    type = lib.types.ints.positive;
    default = 7;
    description = ''
      ゴミ箱へ入れてからこの日数が経ったものを消す。
      Sambaのゴミ箱のように別の仕組みで掃除するものも、保持期間が食い違わないようにここを参照する。
    '';
  };

  config.systemd = {
    services.trash-empty = {
      description = "Remove files older than ${toString days} days from all trash cans";
      after = [
        "local-fs.target"
        "remote-fs.target"
      ];
      serviceConfig = trashHardening // {
        Type = "oneshot";
        TimeoutStartSec = "1h";
        ExecStart = [
          "${pkgs.trash-cli}/bin/trash-empty --all-users -f ${toString days}"
          (lib.getExe emptyStrayTrash)
        ];
        # ゴミ箱の掃除は緊急性がないため、他の処理を最優先する。
        Nice = 19;
        CPUSchedulingPolicy = "idle";
        IOSchedulingClass = "idle";
        IOWeight = 10;
      };
    };
    timers.trash-empty = {
      description = "Daily trash cleanup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
