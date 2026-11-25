# GitHub ActionsのランナのVMが生きているかを確かめる、Mackerelのチェックのコマンド。
#
# `nixos/host/seminar/mackerel.nix`がチェックとして登録する。
#
# ```console
# mackerel-check-github-runner "GitHub Runner x64 dotfiles" fd00::1
# ```
#
# 引数は表示名とVMのアドレス。
# 終了コードはMackerelのチェックの決まりに従い、正常なら0、異常なら2。
#
# ランナのVMは、ホストのGCとストアの最適化の間は毎日わざと止められます。
# 止まっている時間は数分から数十分で、ストアの状態によって変わります。
# 失敗を許す回数を増やして吸収しようとすると、
# 本当に落ちた時に気付くのもその分遅れます。
# そこで応答が無くても、GCか最適化がVMを止めている間は正常として扱います。
# 止める側の定義は`nixos/host/seminar/github-runner/github-runner-x64.nix`の`storeWriterUnits`です。
#
# VMが止まっているのは、サービスの前処理から後処理までの間です。
# サービスが動いているかどうかだけで判断すると、
# 負荷が高くて再試行を待っている間も正常になってしまいます。
# 待っている間はVMを止めていないので、その間にVMが落ちても通知されません。
# そこでユニットの細かい状態を見て、本体か後処理が動いている時だけを正常にします。
# タイムアウトで本体や後処理を止めている途中の状態(`stop-sigkill`や`final-sigterm`など)も、
# VMは止まったままなので正常に入れます。
# 再試行の待ち(`auto-restart`)と、
# 打ち切りの判定(`condition`)と、負荷の検査(`start-pre`)は正常にしません。
#
# 以下の間は、正常として扱われないのに応答が無い状態になります。
# どれも数秒から十数秒なので、チェックの側で1回の失敗を許して吸収します。
#
# - VMを止める前処理が動いている間(負荷の検査と同じ`start-pre`)
# - GCから最適化へ移る間
# - 最適化が終わってからVMが起動し終わるまで
#
# Goで書いているのは、Mackerelのチェックプラグインのエコシステムに合わせるためです。
# pingもユニットの状態も、外部コマンドの出力を読まずにライブラリで直に取ります。
# ICMPのソケットを直に開くので、rootで動かす必要があります。
{
  lib,
  buildGoModule,
  testers,
}:
buildGoModule {
  pname = "mackerel-check-github-runner";
  version = "0.1.0";

  # 動かすものだけをstoreへ入れる。
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./go.sum
      ./main.go
      ./main_test.go
    ];
  };

  vendorHash = "sha256-Zldt2r/3+ebeWX+hVyMcEj56gtqhnRd9+/GNFfRW4jw=";

  # 正常にする条件はsystemdのユニットの状態との組み合わせなので、コンテナの中で実際のユニットを動かす。
  passthru.tests.nixos = import ./nixos-test.nix { inherit testers; };

  meta = {
    description = "Mackerel check plugin that reports whether a GitHub Actions runner VM is alive";
    mainProgram = "mackerel-check-github-runner";
  };
}
