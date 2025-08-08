{ pkgs, ... }:
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
          "${pkgs.xorg.xrandr}/bin/xrandr"
          + " --output HDMI-0 --mode 3840x2160 --pos 3840x0"
          + " --output DP-0 --mode 3840x2160 --pos 0x2160"
          + " --output DP-2 --mode 3840x2160 --pos 7680x2160"
          + " --output DP-4 --mode 3840x2160 --pos 3840x2160 --rate 144 --primary";
        execute_after = [
          "${pkgs.xorg.xrandr}/bin/xrandr --dpi 144"
          "echo 'Xft.dpi: 144}'|${pkgs.xorg.xrdb}/bin/xrdb -merge"
        ];
      }
    ];
  };
}
