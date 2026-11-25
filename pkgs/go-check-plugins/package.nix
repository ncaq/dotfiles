# go-check-plugins - Mackerel公式のチェックプラグイン集
# https://github.com/mackerelio/go-check-plugins
#
# `nixos/host/seminar/mackerel.nix`がチェックのコマンドとして使う。
# nixpkgsには`mackerel-agent`しか無く、プラグイン集は入っていない。
#
# 上流は30個ほどのチェックを1つのモジュールに持っている。
# 使うものだけを`subPackages`に並べてビルドする。
# 別のチェックを使いたくなったらここに足す。
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule (finalAttrs: {
  pname = "go-check-plugins";
  version = "0.53.1";

  src = fetchFromGitHub {
    owner = "mackerelio";
    repo = "go-check-plugins";
    tag = "v${finalAttrs.version}";
    hash = "sha256-l4kabmve/2XnkheZEs+1tAojEnRHBcRU7Yhgqgj5bdk=";
  };

  vendorHash = "sha256-cucV7Nu+hJgogVGx9xcfCr9o/J9HhE1U07o1Q7monds=";

  subPackages = [
    "check-http"
    "check-postgresql"
  ];

  # 上流のテストは外部のホストへ接続するものを含むので、サンドボックスの中では動かせない。
  doCheck = false;

  meta = {
    description = "Check plugins for monitoring written in Go";
    homepage = "https://github.com/mackerelio/go-check-plugins";
    license = lib.licenses.asl20;
  };
})
