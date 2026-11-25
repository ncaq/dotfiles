# GitHub ActionsのランナのVMのランナが、GitHubに登録されていてonlineかを確かめる、Mackerelのチェックのコマンド。
#
# `nixos/host/seminar/mackerel.nix`がチェックとして登録する。
#
# ```console
# mackerel-check-github-runner --label "GitHub Runner x64 dotfiles" \
#   --token-file /run/secrets/github-runner-read-pat \
#   --repository ncaq/dotfiles --runner dotfiles-x64-0
# ```
#
# `--runner`は繰り返して、VMの中の全てのランナを渡す。
# `--api`はテストで偽のAPIへ向けるためのもので、本番では既定の`https://api.github.com`のまま使う。
# 終了コードはMackerelのチェックの決まりに従い、正常なら0、異常なら2。
# GitHubに問い合わせられない時は、ランナの状態が分からないので3(UNKNOWN)を返す。
#
# VMにpingが届くだけでは、ランナがジョブを受け取れるかは分かりません。
# VMが動いていても、ランナの登録に失敗し続けていればジョブは来ません。
# そこでGitHubのAPIでランナの一覧を引いて、
# ランナが登録されていて`online`であることを確かめます。
# トークンはリポジトリの`Administration`を読めれば足ります。
# ランナの一覧を読むのに、これより狭い権限はありません。
#
# ランナはephemeralで、ジョブが終わるたびに登録し直します。
# 登録し直す数秒の間は登録されていない状態になるので、
# チェックの側で1回の失敗を許して吸収します。
#
# ランナのVMは、ホストのGCとストアの最適化の間は毎日わざと止められます。
# 止まっている時間は数分から数十分で、ストアの状態によって変わります。
# 失敗を許す回数を増やして吸収しようとすると、
# 本当に落ちた時に気付くのもその分遅れます。
# そこでランナが登録されていなかったりofflineだったりしても、
# GCか最適化がVMを止めている間は正常として扱います。
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
# 以下の間は、正常として扱われないのにランナが使えない状態になります。
# どれも数秒から十数秒なので、チェックの側で1回の失敗を許して吸収します。
#
# - VMを止める前処理が動いている間(負荷の検査と同じ`start-pre`)
# - GCから最適化へ移る間
# - 最適化が終わってからVMが起動してランナが登録し終わるまで
#
# Goで書いているのは、Mackerelのチェックプラグインのエコシステムに合わせるためです。
# ユニットの状態は、外部コマンドの出力を読まずにライブラリで直に取ります。
# GitHubのAPIは1つのエンドポイントを引くだけなので、標準ライブラリのHTTPで叩きます。
#
# Goの依存はRenovateの対象から外していて、手で更新します。
# 理由は`renovate.json`に書いています。
# 依存を変えたら`vendorHash`も取り直します。
{
  lib,
  buildGoModule,
  testers,
}:
buildGoModule {
  pname = "mackerel-check-github-runner";
  version = "0.2.0";

  # 動かすものだけをstoreへ入れる。
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./go.sum
      (lib.fileset.fileFilter (file: file.hasExt "go") ./.)
    ];
  };

  vendorHash = "sha256-QlrGsIxVnnwvRYGFBouwiIYhtip+SP1BfmT/9jj0m4I=";

  # 正常にする条件はsystemdのユニットの状態との組み合わせなので、コンテナの中で実際のユニットを動かす。
  passthru.tests.nixos = import ./nixos-test.nix { inherit testers; };

  meta = {
    description = "Mackerel check plugin that reports whether the GitHub Actions runners of a VM are online on GitHub";
    mainProgram = "mackerel-check-github-runner";
  };
}
