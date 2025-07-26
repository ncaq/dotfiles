{ pkgs, ... }:
let
  # LG Electronics LG ULTRAGEAR+
  centerFingerprint = "00ffffffffffff001e6dbf5b01010101011e0104b53c2278f919c1ae5044af260e5054210800d1c061404540314001010101010101014dd000a0f0703e803020350058542100001a000000fd0c3090505086010a202020202020000000fc004c4720554c545241474541522b000000ff000a20202020202020202020202002ac02032d7123090707830100004410040301e2006ae305c000e60605017360216d1a0000020b309000047321602909ec00a0a0a0675030203a0058542100001a5a8780a070384d4030203a0058542100001a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000507012790300030128d8060284ff0e9f002f801f006f08910002000400404f0104ff0e9f002f801f006f086200020004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006d90";
  centerConfig = {
    mode = "3840x2160";
    dpi = 144;
    rate = "144";
  };
  # Acer RT280K
  rightFingerprint = "00ffffffffffff0004725f06130050842d1c0103803e22782e08a5a2574fa2280f5054bfef8081c0810081809500b3008140d1c0714f4dd000a0f0703e80303035006d552100001a04740030f2705a80b0588a006d552100001a000000fd00283c1ea03c000a202020202020000000fc00416365722052543238304b0a200162020350f1559001020304051112131f14060720225d5f60616b5e23090707830100006c030c0010003878200040010367d85dc401788003681a00000101283cede305e001e40f000006e6060701606045023a801871382d40582c45006d552100001e565e00a0a0a029502f2035006d552100001a00000000000000000000003d";
  rightConfig = {
    mode = "3840x2160";
    dpi = 144;
    rate = "60";
  };
in
{
  services.autorandr.enable = true;

  # 起動時に正しくprimaryが設定されるようにXサーバの起動を待つようにカスタマイズする。
  systemd.user.services.autorandr = {
    Service = {
      # X11ソケットが作成され、実際に接続可能になるまで待つ
      ExecStartPre = "${pkgs.coreutils}/bin/timeout 10 ${pkgs.bash}/bin/bash -c 'while ! [ -S /tmp/.X11-unix/X0 ] || ! ${pkgs.xorg.xset}/bin/xset q &>/dev/null; do ${pkgs.coreutils}/bin/sleep 0.1; done; ${pkgs.coreutils}/bin/sleep 1'";
    };
  };

  programs.autorandr = {
    enable = true;
    hooks.postswitch = {
      "change-dpi" = ''
        # プライマリディスプレイからDPIを取得して設定
        PRIMARY=$(${pkgs.xorg.xrandr}/bin/xrandr --query|
                  ${pkgs.gnugrep}/bin/grep " primary"|
                  ${pkgs.coreutils}/bin/cut -d' ' -f1)
        DPI=""
        # 設定ファイルからDPIを読み取る
        CONFIG_FILE="$HOME/.config/autorandr/''${AUTORANDR_CURRENT_PROFILE}/config"
        if [ -f "$CONFIG_FILE" ] && [ -n "$PRIMARY" ]; then
          DPI=$(${pkgs.gnugrep}/bin/grep -A 10 "^output $PRIMARY" "$CONFIG_FILE"|
                ${pkgs.gnugrep}/bin/grep "^dpi "|
                ${pkgs.gawk}/bin/awk '{print $2}'|
                ${pkgs.coreutils}/bin/head -1)
        fi
        # DPIが見つかった場合は設定
        if [ -n "$DPI" ]; then
          ${pkgs.xorg.xrandr}/bin/xrandr --dpi "$DPI"
          echo "Xft.dpi: $DPI"|${pkgs.xorg.xrdb}/bin/xrdb -merge
        fi
      '';
    };
    profiles = {
      dominaria-2 = {
        fingerprint = {
          DP-0 = centerFingerprint;
          HDMI-0 = rightFingerprint;
        };
        config = {
          DP-0 = centerConfig // {
            primary = true;
          };
          HDMI-0 = rightConfig // {
            position = "3840x0";
          };
        };
      };
    };
  };
}
