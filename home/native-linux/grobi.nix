{ pkgs, config, ... }:
let
  xrandr = "${pkgs.xrandr}/bin/xrandr";
  xset = "${pkgs.xset}/bin/xset";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  # xrandrとxftの範囲でDPIを設定します。
  dpiIs144 = [
    (xrandr + " --dpi 144")
    "echo 'Xft.dpi: 144'|${pkgs.xrdb}/bin/xrdb -merge"
  ];
  # ラップトップPCの外部ディスプレイへの接続中は動画視聴などを想定し、
  # 画面の自動消灯とスクリーンセーバを無効化します。
  # スクリーンセーバを無効化すると画面のロックも無効化されますが、
  # 動画視聴中に突然画面が消えることを防止するために許容しています。
  # ディスプレイを自宅以外で繋げているケースも少ないですし。
  # どうしても外部ディスプレイを繋げている時にロックしたい時は手動でロックを行ってください。
  # 例えば`loginctl lock-session`を実行すればロックできます。
  inhibitIdle = [
    (xset + " -dpms") # DPMSによる画面消灯を無効化。
    (xset + " s off") # スクリーンセーバを無効化。
  ];
  # 外部ディスプレイを外したときは自動消灯を元に戻す。
  # 宣言的に定義されたサービスが設定値を持っているため、
  # 値を二重管理せずにそれらのサービスを再起動して元の設定に復元する。
  restoreIdle = [
    (systemctl + " --user restart dpms-power.service screensaver-timeout.service")
  ];
in
{
  services.grobi = {
    enable = true;
    rules = [
      {
        name = "dominaria-full";
        # 単一のxrandrコマンドで全て設定。
        # マルチモニタの時に配置できないモニタが出るエラーを回避。
        atomic = true;
        outputs_connected = [
          "HDMI-0-GSM-30470-699895-LG HDR 4K-"
          "DP-0-ACR-1680-2450570038-Acer VG270K-"
          "DP-2-GSM-23487-16843009-LG ULTRAGEAR+-"
          "DP-4-DEL-41599-810963027-AW2725Q-1JYC174"
        ];
        # 凸型配置のためマニュアル設定。
        configure_command =
          xrandr
          + " --output HDMI-0 --mode 3840x2160 --pos 3840x0"
          + " --output DP-0 --mode 3840x2160 --pos 0x2160"
          + " --output DP-2 --mode 3840x2160 --pos 7680x2160"
          + " --output DP-4 --mode 3840x2160 --pos 3840x2160 --rate 144 --primary";
        execute_after = dpiIs144;
      }
      {
        name = "dominaria-tbr"; # Top Bottom Right
        atomic = true;
        outputs_connected = [
          "HDMI-0-GSM-30470-699895-LG HDR 4K-"
          "DP-2-GSM-23487-16843009-LG ULTRAGEAR+-"
          "DP-4-DEL-41599-810963027-AW2725Q-1JYC174"
        ];
        configure_command =
          xrandr
          + " --output HDMI-0 --mode 3840x2160 --pos 3840x0"
          + " --output DP-2 --mode 3840x2160 --pos 7680x2160"
          + " --output DP-4 --mode 3840x2160 --pos 3840x2160 --rate 144 --primary";
        execute_after = dpiIs144;
      }
      {
        name = "dominaria-lbr"; # Left Bottom Right
        atomic = true;
        outputs_connected = [
          "DP-0-ACR-1680-2450570038-Acer VG270K-"
          "DP-2-GSM-23487-16843009-LG ULTRAGEAR+-"
          "DP-4-DEL-41599-810963027-AW2725Q-1JYC174"
        ];
        configure_row = [
          "DP-0-ACR-1680-2450570038-Acer VG270K-"
          "DP-2-GSM-23487-16843009-LG ULTRAGEAR+-"
          "DP-4-DEL-41599-810963027-AW2725Q-1JYC174"
        ];
        execute_after = dpiIs144;
      }
      {
        name = "dominaria-tlr"; # Top Left Right
        atomic = true;
        outputs_connected = [
          "HDMI-0-GSM-30470-699895-LG HDR 4K-"
          "DP-0-ACR-1680-2450570038-Acer VG270K-"
          "DP-2-GSM-23487-16843009-LG ULTRAGEAR+-"
        ];
        configure_command =
          xrandr
          + " --output HDMI-0 --mode 3840x2160 --pos 1920x0"
          + " --output DP-0 --mode 3840x2160 --pos 0x2160"
          + " --output DP-2 --mode 3840x2160 --pos 3840x2160 --primary";
        execute_after = dpiIs144;
      }
      {
        name = "dominaria-tlb"; # Top Left Bottom
        atomic = true;
        outputs_connected = [
          "HDMI-0-GSM-30470-699895-LG HDR 4K-"
          "DP-0-ACR-1680-2450570038-Acer VG270K-"
          "DP-4-DEL-41599-810963027-AW2725Q-1JYC174"
        ];
        configure_command =
          xrandr
          + " --output HDMI-0 --mode 3840x2160 --pos 3840x0"
          + " --output DP-0 --mode 3840x2160 --pos 0x2160"
          + " --output DP-4 --mode 3840x2160 --pos 3840x2160 --rate 144 --primary";
        execute_after = dpiIs144;
      }
      {
        name = "dominaria-t"; # Top
        outputs_connected = [
          "HDMI-0-GSM-30470-699895-LG HDR 4K-"
        ];
        execute_after = dpiIs144;
      }
      {
        name = "dominaria-l"; # Left
        outputs_connected = [
          "DP-0-ACR-1680-2450570038-Acer VG270K-"
        ];
        execute_after = dpiIs144;
      }
      {
        name = "dominaria-r"; # Right
        outputs_connected = [
          "DP-2-GSM-23487-16843009-LG ULTRAGEAR+-"
        ];
        execute_after = dpiIs144;
      }
      {
        name = "dominaria-b"; # Bottom
        outputs_connected = [
          "DP-4-DEL-41599-810963027-AW2725Q-1JYC174"
        ];
        # Alienware AW2725Qは144Hzが最大ではないけれど4Kの場合144Hzが適切なのでマニュアル設定。
        configure_command = xrandr + " --output DP-4 --mode 3840x2160 --rate 144 --primary";
        execute_after = dpiIs144;
      }
      {
        # ラップトップPCと外部ディスプレイ(テレビ想定)をHDMIで接続したときの設定。
        name = "laptop-docking-tv";
        atomic = true;
        outputs_connected = [
          "HDMI-1"
          "eDP-1"
        ];
        configure_column = [
          "HDMI-1"
          "eDP-1"
        ];
        primary = "eDP-1";
        execute_after = inhibitIdle;
      }
      {
        # ラップトップ向けのfallback設定。
        name = "eDP-1";
        configure_single = "eDP-1";
        # テレビ接続を外したら、
        # 自動消灯とスクリーンセーバタイムアウトを元に戻す。
        # PC起動時に初回として無駄にサービスが起動されるおそれがありますが、
        # 軽いサービスなので許容します。
        execute_after = restoreIdle;
      }
    ];
  };
  # `services.grobi`に設定する値や、
  # 現在適用されている設定を、
  # 簡単に確認できるようにするためPATHに実行バイナリを追加します。
  home.packages = [
    config.services.grobi.package
  ];
}
