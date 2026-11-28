{
  pkgs,
  lib,
  config,
  ...
}:
let
  # 復帰からモニタのEDID読み取りが安定するまでの待ち時間(秒)。
  # 消灯からの復帰直後はEDID読み取りが一時的に不安定で、
  # grobiが「monitor has changed」として出力を無効化・再構成し、
  # XMonadのrescreenでワークスペースとウィンドウの配置が崩れることが、
  # bulletのDP-0(Acer VG270K)で実測により確認されています。
  # 実測では復帰の数秒後に一時イベントが発生したため、
  # 余裕を持たせた値にしています。
  grobiResumeDelay = "20";

  # grobiの中断と再開にはサービスのstop/startではなくSIGSTOP/SIGCONTを使います。
  # grobiは適用済みのルール名をプロセスのメモリ上にしか持たないため、
  # プロセスを作り直すと現在の構成が既に正しくても初回のルール適用が必ず走ります。
  # bulletのDP-0(Acer VG270K)は消灯からの復帰時に一度disconnectして、
  # 物理サイズが暫定値に化けた状態で再接続されるため、
  # ここでルールを適用するxrandrは全画面のモードセットを伴い、
  # 実測で約2秒かけて画面が一度落ちてから復帰していました。
  # 再開が遅延実行される仕組みの都合上、
  # これは復帰してしばらく経ってから画面が落ちる形で体感されます。
  # プロセスを凍らせるだけならば適用済みのルール名が保持されるので、
  # 復帰後に構成が変わっていなければxrandrは一切実行されず画面も落ちません。
  # 中断中に届いたRandRイベントは再開後にまとめて処理されますが、
  # grobiはイベントごとに現在の出力構成を取り直して判定するため、
  # 中断中の一時的な変化は無視され、
  # 実際に構成が変わっていた場合のみ新しいルールが適用されます。
  # 副作用として復帰後のDP-0は物理サイズの報告が暫定値のまま残りますが、
  # DPIは`xrandr --dpi`とXft.dpiで固定しているため表示への影響はありません。
  #
  # `systemd-run`のコマンドとしても渡すためsystemctlはフルパスで指定します。
  grobiSignal =
    signal:
    "${lib.getExe' config.systemd.package "systemctl"} --user kill --kill-whom=main --signal=${signal} grobi.service";

  # 猶予時間内の復帰でロックされていなければgrobiを再開します。
  # 猶予超過でロックに進んだ場合はロッカー側が解除後に再開するため、
  # ここでは再開しません。
  grobiResumeIfUnlocked = pkgs.writeShellApplication {
    name = "grobi-resume-if-unlocked";
    runtimeInputs = with pkgs; [
      procps
    ];
    text = ''
      if ! pgrep -x xsecurelock > /dev/null; then
        # 再開に失敗するとgrobiが中断したままになるため、
        # 気付けるようにエラーログを残します。
        ${grobiSignal "SIGCONT"} ||
          echo "grobi-resume-if-unlocked: failed to resume grobi.service (exit=$?)" >&2
      fi
    '';
  };

  # 無操作による消灯時にxss-lockから起動されるnotifier。
  # 消灯中と復帰直後のRandRイベントでレイアウトが崩れないようにgrobiを中断します。
  # 自身が殺される時に、
  # 遅延実行のtransientユニットでgrobiの再開を予約します。
  # xss-lockに殺されてもgrobiの再開が実行されるように、
  # このプロセスの子ではなくsystemdのユニットとして予約します。
  screenBlankNotifier = pkgs.writeShellApplication {
    name = "screen-blank-notifier";
    runtimeInputs = [
      config.systemd.package
      pkgs.coreutils
    ];
    text = ''
      # grobiの中断に失敗しても本来の役目には支障がないので、
      # エラーログを残した上で続行します。
      ${grobiSignal "SIGSTOP"} ||
        echo "screen-blank-notifier: failed to suspend grobi.service (exit=$?)" >&2
      sleep_pid=""
      on_term() {
        if [ -n "$sleep_pid" ]; then
          kill "$sleep_pid" 2> /dev/null || true
        fi
        systemd-run --user --collect --on-active=${grobiResumeDelay} \
          --timer-property=AccuracySec=1s \
          ${lib.getExe grobiResumeIfUnlocked}
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

  # xsecurelockのラッパ。
  # 手動ロック(loginctl lock-session)やサスペンドでは、
  # notifierを経由せずlockerが直接起動されるため、
  # ここでもgrobiを中断します。
  xsecurelockGrobiPause = pkgs.writeShellApplication {
    name = "xsecurelock-grobi-pause";
    runtimeInputs = [
      config.systemd.package
      pkgs.xsecurelock
    ];
    text = ''
      # `writeShellApplication`はerrexitを注入するため、
      # ここでgrobiの中断が失敗するとxsecurelockの起動前にラッパが終了し、
      # 画面がロックされないまま放置されるfail-openになってしまいます。
      # ロックの起動を最優先するため、
      # 中断の失敗はエラーログを残した上で続行します。
      ${grobiSignal "SIGSTOP"} ||
        echo "xsecurelock-grobi-pause: failed to suspend grobi.service (exit=$?)" >&2
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
      systemd-run --user --collect --on-active=${grobiResumeDelay} \
        --timer-property=AccuracySec=1s \
        ${grobiSignal "SIGCONT"}
    '';
  };
in
{
  # xsecurelock用PAMサービスでU2F有効化。
  # U2Fの鍵の設定は`nixos/native-linux/pam-u2f.nix`にあります。
  security.pam.services.xsecurelock.u2fAuth = true;

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
