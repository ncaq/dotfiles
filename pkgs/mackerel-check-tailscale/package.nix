# このホストがtailnetに繋がっているかを確かめる、Mackerelのチェックのコマンド。
#
# `nixos/host/seminar/mackerel.nix`がチェックとして登録する。
# 引数は取らない。
# 終了コードはMackerelのチェックの決まりに従い、正常なら0、異常なら2。
#
# tailscaledが動いているだけでなく、
# コントロールプレーンからこのノードがオンラインに見えていることまで確かめます。
# この2つを両方見る既存のチェックのプラグインは見つかりませんでした。
#
# Goで書いているのは、
# Mackerelのチェックプラグインのエコシステムも、
# Tailscaleが公式に提供しているローカルAPIのクライアントもGoだからです。
# `tailscale status --json`の出力を読むのではなく、
# 公式のクライアントでtailscaledへ直に問い合わせます。
{
  lib,
  buildGo127Module,
}:
# `tailscale.com`のモジュールが要求するGoの版が、既定のGoより新しい。
buildGo127Module {
  pname = "mackerel-check-tailscale";
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

  vendorHash = "sha256-DT77QCjv/gdTKtjkP6CpgY/utAlSnB9uBJs3SubmsvM=";

  meta = {
    description = "Mackerel check plugin that reports whether this node is connected to the tailnet";
    mainProgram = "mackerel-check-tailscale";
  };
}
