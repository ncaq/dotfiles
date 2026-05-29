{ pkgs, lib, ... }:
let
  # 共通originで登録するクレデンシャル。
  # 自分の所有するマシンを自分の所有するYubiKeyでロック解除できても何も困らないため、
  # 全ホストで有効にしています。
  # 登録コマンド: `pamu2fcfg -n -o pam://ncaq.net`
  # 先頭の`:`を除いて貼ります。
  u2fKeys = {
    # Device type: YubiKey 5 NFC
    # Serial number: 9074075
    # Firmware version: 5.1.2
    # 外に持ち出さずにデスクトップPCで使用しています。
    shiroko = "dYCSbSsCSK8fe3jC3vj139CprL3RP6Bgz6XS4+j5vWGc9ouOGXL9hBtzstKGdqHJK5zj9pvtLEG9xW3uqn9B8Q==,0cHOhDvjY2u8Fh9dAn8M/9xJAKVrYh2oIk1kksECgU7xxjcQJx+vBE9L3VCGRR69QX9+SMGlPB6ohkhdpto+Mg==,es256,+presence%";
    # Device type: YubiKey Bio - FIDO Edition
    # Serial number: 34849987
    # Firmware version: 5.7.4
    # ラップトップPCに繋いで持ち歩きます。
    # 回数制限のある指紋認証を要求するため仮に盗難されてもリスクはほぼありません。
    alice = "+nkdBXuOuCKqJ41VEal3/kJaET23fIQzBEky8PgTKEaGfAAu7lmpvjey1Fai4cSNHZvnx7GPOWZJryfvMXZoFQ==,B7lUv5xvIO6UUhd3OMzBhlNaGCKwfHBb/aXBzxf1E1PvOI09uYq+Ot+seZhMwCUti3NDS3Ina06thkmE4NRPPw==,es256,+presence";
  };
in
{
  security.pam = {
    # FIDO2(U2F) PAM認証。
    u2f = {
      enable = true;
      # パスワードでもYubiKeyでもどちらでもログインできます。
      # セキュリティキー側で認証を行うことを前提にしています。
      control = "sufficient";
      settings = {
        authfile = pkgs.writeText "u2f-mappings" (
          "ncaq:" + lib.concatStringsSep ":" (lib.attrValues u2fKeys)
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
