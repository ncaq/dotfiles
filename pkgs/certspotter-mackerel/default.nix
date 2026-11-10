# certspotterが検知したイベントをMackerelのチェックへ繋ぐ2つのコマンド。
#
# - `certspotter-hook`: certspotterのhookとして、イベントを1行のJSONでログへ追記する
# - `check-certspotter`: Mackerelのチェックとして、ログに最近のイベントがあればCRITICALにする
#
# `nixos/host/seminar/certspotter.nix`から呼ばれます。
#
# シェルではなくHaskellで書いています。
# `SUMMARY`や`ISSUER_DN`やSANはCA/CTログ由来の信頼できない値で、
# シェルで制御文字を潰すだけでは漏れが出やすいためです。
# aesonに記録と読み取りの両方を任せれば、
# 改行やタブが入っても列ずれや偽の行は構造的に起きません。
# unliftioは`IO`を直接書かずに`MonadIO`と`MonadUnliftIO`で抽象化するために使います。
#
# ビルドの中で`test.bash`が2つのプログラムを突き合わせて検査します。
{
  lib,
  runCommand,
  makeWrapper,
  shellcheck,
  writers,
  systemd,
  # hookが追記してチェックが読むログ。
  eventsLog,
  # この秒数以内のイベントがあればチェックをCRITICALにします。
  alertWindowSeconds,
  # チェックが動いていることを確かめるsystemdのユニット。
  serviceUnit,
}:
let
  haskellArgs = {
    libraries = hpkgs: [
      hpkgs.aeson
      hpkgs.unliftio
    ];
    ghcArgs = [
      "-Wall"
      "-Wcompat"
      "-Widentities"
      "-Wincomplete-record-updates"
      "-Wincomplete-uni-patterns"
      "-Wpartial-fields"
      "-Wredundant-constraints"
      "-Werror"
    ];
  };
  # 設定は環境変数で受け取るので、ラッパーで包む前のプログラムは設定に依らず共有されます。
  hook = writers.writeHaskellBin "certspotter-hook" haskellArgs ./certspotter-hook.hs;
  check = writers.writeHaskellBin "check-certspotter" haskellArgs ./check-certspotter.hs;
in
runCommand "certspotter-mackerel"
  {
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
  }
  ''
    shellcheck ${./test.bash}
    bash ${./test.bash} ${lib.getExe hook} ${lib.getExe check}

    makeWrapper ${lib.getExe hook} $out/bin/certspotter-hook \
      --set CERTSPOTTER_EVENTS_LOG ${lib.escapeShellArg eventsLog}
    makeWrapper ${lib.getExe check} $out/bin/check-certspotter \
      --set CERTSPOTTER_EVENTS_LOG ${lib.escapeShellArg eventsLog} \
      --set CERTSPOTTER_ALERT_WINDOW_SECONDS ${toString alertWindowSeconds} \
      --set CERTSPOTTER_SERVICE_UNIT ${lib.escapeShellArg serviceUnit} \
      --prefix PATH : ${lib.makeBinPath [ systemd ]}
  ''
