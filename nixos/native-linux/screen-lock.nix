{ pkgs, lib, ... }:
let
  # 共通originで登録したクレデンシャル。
  # 自分の所有するマシンを、
  # 自分の所有するYubiKeyで、
  # 自分の指紋でロック解除できても何も困らないため、
  # 全ホストで有効にしています。
  # 登録コマンド: `pamu2fcfg -n -o pam://ncaq.net`
  # 先頭の`:`を除いて貼ります。
  u2fKeys = {
    # Device type: YubiKey Bio - FIDO Edition
    # Serial number: 34849987
    # Firmware version: 5.7.4
    alice = "+nkdBXuOuCKqJ41VEal3/kJaET23fIQzBEky8PgTKEaGfAAu7lmpvjey1Fai4cSNHZvnx7GPOWZJryfvMXZoFQ==,B7lUv5xvIO6UUhd3OMzBhlNaGCKwfHBb/aXBzxf1E1PvOI09uYq+Ot+seZhMwCUti3NDS3Ina06thkmE4NRPPw==,es256,+presence";
  };
in
{
  security.pam = {
    # FIDO2(U2F) PAM認証。
    u2f = {
      enable = true;
      # パスワードでもYubiKey指紋でもどちらでもOK。
      # YubiKey Bioの指紋認証のようにセキュリティキー側で認証を行うことを前提にしています。
      control = "sufficient";
      settings = {
        authfile = pkgs.writeText "u2f-mappings" (
          "ncaq:${lib.concatStringsSep ":" (lib.attrValues u2fKeys)}"
        );
        origin = "pam://ncaq.net";
        cue = true; # "Please touch the device." を表示。
      };
    };
    # xsecurelock用PAMサービスでU2F有効化。
    services.xsecurelock.u2fAuth = true;
  };

  # xss-lock: systemdのlock-session/suspend等のイベントでロッカーを自動起動。
  programs.xss-lock = {
    enable = true;
    # i3lockなどに比べてクラッシュ耐性などが多少堅牢らしいのでxsecurelockを指定。
    lockerCommand = "${pkgs.xsecurelock}/bin/xsecurelock";
  };
}
