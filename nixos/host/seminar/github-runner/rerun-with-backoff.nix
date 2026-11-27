/**
  終わるたびに起動し直すサービスを、失敗が続く時だけ間隔を空けて起動し直します。

  ephemeralなGitHub Actionsのランナは、ジョブを1つ終えると登録を解除して正常終了します。
  起動し直せば登録し直すので、成功で終わった時はすぐ起動し直したいです。
  失敗で終わった時も起動し直せば直りますが、
  回線が切れている間のようにすぐには直らない失敗もあるので、
  同じ間隔で試し続けるとGitHubへの登録の試行を連打することになります。

  systemdの指数バックオフ(`RestartSteps`)は、
  自動の再起動の回数で間隔を決めて、成功で終わった再起動も数えます。
  長く動いた後でも回数は戻りません。
  `Restart=always`と組み合わせると、
  ジョブを数回こなした後は、次の登録が毎回最大の間隔まで待たされます。
  どちらも一時的なユニットで試して確かめました。

  そこで自動の再起動は失敗の時だけにして、
  成功で終わった時は`OnSuccess=`で呼ばれる別のユニットが起動し直します。
  自動の再起動ではない起動なので、回数が0に戻り、次の失敗はまた最短の間隔から始まります。

  間隔は5秒から始まり、14秒、39秒、108秒と伸びて、5分で頭打ちになります。
  5秒は公式のラッパが再試行できるエラーで待つ時間です。
  回数では諦めません。
  VMが強制終了された後は、前のセッションが切れるまで10分ほど登録に失敗し続けるからです。
  最短でも5秒空くので、systemdの起動回数の上限(10秒に5回)には届きません。

  `OnSuccess=`は手で止めた時にも呼ばれるので、
  対象のサービスは`systemctl stop`しても起動し直されます。
  止めておきたい時は、先に`<名前>-rerun.service`を`systemctl mask --runtime`します。
  シャットダウンの時は、起動のジョブが停止のジョブと衝突して断られるので、起動し直されません。

  ランナのVMの中で読み込むモジュールですが、
  このディレクトリのモジュールはホストにも読み込まれます。
  ホストでは対象が空なので何もしません。
*/
{ lib, config, ... }:
let
  cfg = config.local.rerunWithBackoff;
  # 稼働中のsystemdと同じパッケージの`systemctl`。
  systemctl = lib.getExe' config.systemd.package "systemctl";
  # 成功で終わったサービスを起動し直すユニットの名前。
  rerunUnitOf = unit: "${unit}-rerun";
in
{
  options.local.rerunWithBackoff = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "github-runner-dotfiles-x64-0" ];
    description = ''
      Names of services, without the `.service` suffix, that are started again
      whenever they exit: at once after a success, and with exponential backoff
      while they keep failing.
    '';
  };

  config.systemd.services = lib.mkMerge (
    map (unit: {
      ${unit} = {
        onSuccess = [ "${rerunUnitOf unit}.service" ];
        serviceConfig = {
          # 対象のサービスを定義するモジュールの値を上書きします。
          # github-runnersモジュールは`on-success`を通常の優先度で定義しています。
          Restart = lib.mkForce "on-failure";
          RestartSec = "5s";
          RestartSteps = 4;
          RestartMaxDelaySec = "5min";
        };
      };
      ${rerunUnitOf unit} = {
        description = "Start ${unit} again after it exited successfully";
        serviceConfig = {
          Type = "oneshot";
          # 起動を待つと、対象が動いている間このユニットが終わりません。
          # 衝突するジョブがある時は断らせて、シャットダウンの途中で起動し直さないようにします。
          ExecStart = "${systemctl} start --no-block --job-mode=fail ${unit}.service";
        };
      };
    }) cfg
  );
}
