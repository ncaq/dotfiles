# ゴミ箱の期限切れを定期的に掃除するNixOSモジュール。
#
# 2つのユニットを定義します。
#
# - `trash-empty.service`: `trash-cli`の`trash-empty --all-users`で、通常の場所にあるゴミ箱を掃除する
# - `trash-empty-stray.service`: `trash-empty --all-users`が見つけられないゴミ箱を、このパッケージで探して掃除する
#
# ユニットを分けているので、片方が失敗してももう片方は動き、失敗はそれぞれのユニットの結果に出ます。
#
# ユニットの権限の絞り込みは、コマンドが何をするかと対になっているので、パッケージの隣に置いています。
# 使う側(`nixos/core/trash.nix`)は、何日残すかだけを決めます。
# テスト(`nixos-test.nix`)もこのモジュールだけを読むので、パッケージがホストの構成に依存しません。
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.services.trash-empty;
  hardening = import ../../lib/systemd-hardening.nix;
  # ゴミ箱はホームやマウント先や/tmpにあるので、
  # それらを不可視またはread-onlyにする隔離は適用できない。
  baseServiceConfig =
    removeAttrs hardening.isolated [
      "PrivateTmp"
      "ProtectHome"
      "ProtectSystem"
    ]
    // {
      Type = "oneshot";
      TimeoutStartSec = "1h";
      # ゴミ箱の掃除は緊急性がないため、他の処理を最優先する。
      Nice = 19;
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
      IOWeight = 10;
    };
  dailyTimer = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
in
{
  options.services.trash-empty = {
    enable = lib.mkEnableOption "ゴミ箱の期限切れの定期的な掃除";
    retentionDays = lib.mkOption {
      type = lib.types.ints.positive;
      description = "ゴミ箱へ入れてからこの日数が経ったものを消す。";
    };
    stray = {
      package = lib.mkPackageOption pkgs "trash-empty-stray" { };
      roots = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = import ./stray-roots.nix { inherit lib; } config.fileSystems;
        defaultText = lib.literalExpression "import ./stray-roots.nix { inherit lib; } config.fileSystems";
        description = ''
          `trash-empty --all-users`が見つけられないゴミ箱を探す起点。絶対パスで指定する。
          起点と違うデバイスのディレクトリへは降りないので、
          起点の下にマウントしているファイルシステムも探す時は、それも起点として並べる。
          既定の決め方は`stray-roots.nix`に書いてある。
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services = {
        trash-empty = {
          description = "Remove files older than ${toString cfg.retentionDays} days from all trash cans";
          after = [
            "local-fs.target"
            "remote-fs.target"
          ];
          serviceConfig = baseServiceConfig // {
            # rootが他ユーザ所有のゴミ箱を走査・削除するために必要な権限だけを残す。
            CapabilityBoundingSet = [
              "CAP_DAC_OVERRIDE"
              "CAP_FOWNER"
            ];
            ExecStart = "${lib.getExe' pkgs.trash-cli "trash-empty"} --all-users -f ${toString cfg.retentionDays}";
          };
        };
        trash-empty-stray = {
          description = "Remove files older than ${toString cfg.retentionDays} days from stray trash cans";
          after = [ "local-fs.target" ];
          serviceConfig = baseServiceConfig // {
            # 他のユーザが所有するディレクトリを辿るための権限と、
            # 見つけたゴミ箱を所有者の権限で掃除するためにuidとgidを変える権限だけを残す。
            # 一般ユーザのゴミ箱は権限を落として掃除するので、
            # 前者を掃除に使うのはrootが所有するゴミ箱の時だけになる。
            CapabilityBoundingSet = [
              "CAP_DAC_OVERRIDE"
              "CAP_FOWNER"
              "CAP_SETGID"
              "CAP_SETUID"
            ];
            ExecStart = lib.escapeShellArgs (
              [
                (lib.getExe cfg.stray.package)
                "sweep"
                "--days"
                (toString cfg.retentionDays)
              ]
              ++ cfg.stray.roots
            );
          };
        };
      };
      timers = {
        trash-empty = dailyTimer // {
          description = "Daily trash cleanup";
        };
        trash-empty-stray = dailyTimer // {
          description = "Daily stray trash cleanup";
        };
      };
    };
  };
}
