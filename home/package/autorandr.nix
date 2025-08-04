{ pkgs, ... }:
let
  # LG Electronics LG ULTRAGEAR+
  lgUltragearFingerprint = "00ffffffffffff001e6dbf5b01010101011e0104b53c2278f919c1ae5044af260e5054210800d1c061404540314001010101010101014dd000a0f0703e803020350058542100001a000000fd0c3090505086010a202020202020000000fc004c4720554c545241474541522b000000ff000a20202020202020202020202002ac02032d7123090707830100004410040301e2006ae305c000e60605017360216d1a0000020b309000047321602909ec00a0a0a0675030203a0058542100001a5a8780a070384d4030203a0058542100001a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000507012790300030128d8060284ff0e9f002f801f006f08910002000400404f0104ff0e9f002f801f006f086200020004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006d90";
  lgUltragearConfig = {
    mode = "3840x2160";
    dpi = 144;
    rate = "144";
  };
  # LG HDR 4K(HDMI)
  lgHdr4kFingerprint = "00ffffffffffff001e6d0677f7ad0a00031f0103803c2278ea3e31ae5047ac270c50542108007140818081c0a9c0d1c081000101010108e80030f2705a80b0588a0058542100001e04740030f2705a80b0588a0058542100001a000000fd00283d1e873c000a202020202020000000fc004c472048445220344b0a202020013e020344714d9022201f1203040161605d5e5f230907076d030c001000b83c20006001020367d85dc401788003e30f0003681a00000101283d00e305c000e606050152485d023a801871382d40582c450058542100001e565e00a0a0a029503020350058542100001a0000000000000000000000000000000000000000000000f1";
  lgHdr4kConfig = {
    mode = "3840x2160";
    dpi = 144;
  };
  # Acer VG270K
  acerVg270kFingerprint = "00ffffffffffff000472900636bb1092151d0104b53c22783bf6d5a7544b9e250d50542308008140818081c081009500b300d1c001014dd000a0f0703e8030203500544f2100001a565e00a0a0a0295030203500544f2100001e000000fd00283ca0a03c010a202020202020000000fc00416365722056473237304b0a2001be02032bf150010304121305141f9007025d5e5f606123090707830100006d030c0010003878200060010203023a801871382d40582c4500544f2100001e011d007251d01e206e285500544f2100001e8c0ad08a20e02d10103e9600544f21000018000000000000000000000000000000000000000000000000000000000000f8";
  acerVg270kConfig = {
    mode = "3840x2160";
    dpi = 144;
  };
  # Acer RT280K
  acerRt280kFingerprint = "00ffffffffffff0004725f06130050842d1c0104b53e22783f08a5a2574fa2280f5054bfef8081c0810081809500b3008140d1c0714f4dd000a0f0703e80302035006d552100001ab46600a0f0701f80082018046d552100001a000000fd00283ca0a03c010a202020202020000000fc00416365722052543238304b0a200121020329f14f9001020304051112131f140607202223090707830100006c030c00100038782000400103023a801871382d40582c45006d552100001e011d007251d01e206e2855006d552100001e565e00a0a0a029502f2035006d552100001a0000000000000000000000000000000000000000000000000000000000000000c1";
  acerRt280kConfig = {
    mode = "3840x2160";
    dpi = 144;
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
      dominaria-TLB = {
        fingerprint = {
          HDMI-0 = lgHdr4kFingerprint;
          DP-0 = acerVg270kFingerprint;
          DP-4 = lgUltragearFingerprint;
        };
        config = {
          # top
          HDMI-0 = lgHdr4kConfig // {
            position = "3840x0";
          };
          # left
          DP-0 = acerVg270kConfig // {
            position = "0x2160";
          };
          # bottom
          DP-4 = lgUltragearConfig // {
            primary = true;
            position = "3840x2160";
          };
        };
      };
      dominaria-full = {
        fingerprint = {
          HDMI-0 = lgHdr4kFingerprint;
          DP-0 = acerVg270kFingerprint;
          DP-2 = acerRt280kFingerprint;
          DP-4 = lgUltragearFingerprint;
        };
        config = {
          # top
          HDMI-0 = lgHdr4kConfig // {
            position = "3840x0";
          };
          # left
          DP-0 = acerVg270kConfig // {
            position = "0x2160";
          };
          # right
          DP-2 = acerRt280kConfig // {
            position = "7680x2160";
          };
          # bottom
          DP-4 = lgUltragearConfig // {
            primary = true;
            position = "3840x2160";
          };
        };
      };
    };
  };
}
