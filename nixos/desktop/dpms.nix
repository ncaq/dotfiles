# デスクトップの画面消灯とロック猶予のタイムアウト設定。
# GPUの例えばRTX 5090は、
# 画面点灯中はマルチモニタ制約でメモリクロックを下げられず約48W消費しますが、
# 消灯中はP8ステートに落ちて約21Wになるため、
# 発熱対策として離席時は画面を消灯させます。
# OLEDモニターの焼き付き防止の意味もあります。
{ lib, pkgs, ... }:
{
  systemd.user.services.dpms-timeout = {
    description = "Configure screen saver and DPMS timeout";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe (
        pkgs.writeShellApplication {
          name = "dpms-timeout";
          runtimeInputs = with pkgs; [ xset ];
          text = ''
            # スクリーンセーバーのタイムアウトを設定。
            # 30分の無操作で消灯してxss-lockのnotifierが起動され、
            # サイクル時間の8時間が経過するとlockerが起動されます。
            # つまり消灯から8時間以内の復帰ならロックされていません。
            # 動画を見ていても大抵は30分に収まります。
            # 自宅のデスクトップなのでロックまでの猶予は長めで実質無制限にしています。
            # 仕組みの詳細は`native-linux/screen-lock.nix`を参照。
            xset s 1800 28800
            # DPMSを有効化
            xset +dpms
            # スクリーンセーバー発動の直後にDPMSでモニタの電源を切ります。
            # (スタンバイ:30.5分, サスペンド:30.75分, オフ:31分)
            # スクリーンセーバーのタイムアウトより後にすることで、
            # ロックの起点が常にnotifier経由になるようにします。
            xset dpms 1830 1845 1860
          '';
        }
      );
      Restart = "always";
      RestartSec = "10s";
    };
    wantedBy = [ "graphical-session.target" ];
  };
}
