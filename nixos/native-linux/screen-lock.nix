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

  # 復帰からモニタのEDID読み取りが安定するまでの待ち時間(秒)。
  # 消灯からの復帰直後はEDID読み取りが一時的に不安定で、
  # grobiが「monitor has changed」として出力を無効化・再構成し、
  # XMonadのrescreenでワークスペースとウィンドウの配置が崩れることが、
  # bulletのDP-0(Acer VG270K)で実測により確認されています。
  # 実測では復帰の数秒後に一時イベントが発生したため、
  # 余裕を持たせた値にしています。
  grobiRestartDelay = "20";

  # 猶予時間内の復帰でロックされていなければgrobiを再開します。
  # 猶予超過でロックに進んだ場合はロッカー側が解除後に再開するため、
  # ここでは再開しません。
  grobiStartIfUnlocked = pkgs.writeShellApplication {
    name = "grobi-start-if-unlocked";
    runtimeInputs = with pkgs; [
      procps
      systemd
    ];
    text = ''
      if ! pgrep -x xsecurelock > /dev/null; then
        systemctl --user start grobi.service
      fi
    '';
  };

  # 無操作による消灯時にxss-lockから起動されるnotifier。
  # 消灯中と復帰直後のRandRイベントでレイアウトが崩れないようにgrobiを止めます。
  # 自身が殺される時に、
  # 遅延起動のtransientユニットでgrobiの再開を予約します。
  # xss-lockに殺されてもgrobiの再開が実行されるように、
  # このプロセスの子ではなくsystemdのユニットとして予約します。
  screenBlankNotifier = pkgs.writeShellApplication {
    name = "screen-blank-notifier";
    runtimeInputs = with pkgs; [
      coreutils
      systemd
    ];
    text = ''
      systemctl --user stop grobi.service
      sleep_pid=""
      on_term() {
        if [ -n "$sleep_pid" ]; then
          kill "$sleep_pid" 2> /dev/null || true
        fi
        systemd-run --user --collect --on-active=${grobiRestartDelay} \
          ${lib.getExe grobiStartIfUnlocked}
        exit 0
      }
      trap on_term TERM INT
      # SIGTERMを受け取るまで待機し続けます。
      while :; do
        sleep 3600 &
        sleep_pid=$!
        wait "$sleep_pid" || true
      done
    '';
  };

  # xsecurelockのラッパー。
  # 手動ロック(loginctl lock-session)やサスペンドでは、
  # notifierを経由せずlockerが直接起動されるため、
  # ここでもgrobiを停止します。
  xsecurelockGrobiPause = pkgs.writeShellApplication {
    name = "xsecurelock-grobi-pause";
    runtimeInputs = with pkgs; [
      systemd
      xsecurelock
    ];
    text = ''
      systemctl --user stop grobi.service
      locker_pid=""
      on_term() {
        if [ -n "$locker_pid" ]; then
          kill "$locker_pid" 2> /dev/null || true
        fi
      }
      trap on_term TERM INT
      xsecurelock &
      locker_pid=$!
      wait "$locker_pid" || true
      # 解除後にモニタのEDIDが安定してからgrobiを再開します。
      systemd-run --user --collect --on-active=${grobiRestartDelay} \
        systemctl --user start grobi.service
    '';
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
  # notifierとlockerの2段階の仕組みで画面ロックに猶予時間を設けています。
  # - 無操作で`xset s TIMEOUT CYCLE`のTIMEOUTに達するとnotifierが起動され、
  #   活動再開かlockerの起動時にSIGTERMで殺されます。
  # - lockerはさらにCYCLE秒が経過してから起動されます。
  # つまりCYCLEが猶予時間になり、
  # その間に復帰すればnotifierが殺されるだけで認証は発生しません。
  # タイムアウトと猶予時間の値は環境ごとに設定します。
  # - デスクトップ: `nixos/desktop/dpms.nix`
  # - ラップトップ: `nixos/laptop/screen-lock-time.nix`
  programs.xss-lock = {
    enable = true;
    extraOptions = [ "--notifier=${lib.getExe screenBlankNotifier}" ];
    # i3lockなどに比べてクラッシュ耐性などが多少堅牢らしいのでxsecurelockを指定。
    lockerCommand = lib.getExe xsecurelockGrobiPause;
  };
}
