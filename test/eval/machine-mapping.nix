# seminarの`machineAddresses`に掛けている検査が、
# 壊れた宣言で落ちて、正しい宣言では落ちないことを確かめる。
#
# 実機の宣言は正しいので、
# 検査が働かなくなっても評価は通ったまま気付けない。
# 以下を見る。
#
# - 書き方だけが違う同じアドレスを、重複として扱うこと
# - IPv4を導けない形のアドレスを止めること
# - インターネットへ出ないマシンにIPv4を持たせたら止めること
#
# `machine-mapping.nix`だけを`lib.evalModules`で読み込み、
# 参照している他のオプションは最小の形で用意する。
{ lib }:
let
  stub = {
    options = {
      assertions = lib.mkOption {
        type = lib.types.listOf lib.types.unspecified;
        default = [ ];
      };
      # NATの設定を受けるだけ。
      networking = lib.mkOption {
        type = lib.types.anything;
        default = { };
      };
      microvm.vms = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
      local.machineEgress = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
    };
  };
  # 落ちた検査のメッセージの一覧。
  failures =
    { machineAddresses, machineEgress }:
    let
      evaluated = lib.evalModules {
        modules = [
          ../../nixos/host/seminar/machine-mapping.nix
          stub
          {
            inherit machineAddresses;
            local.machineEgress = machineEgress;
          }
        ];
      };
    in
    map (a: a.message) (lib.filter (a: !a.assertion) evaluated.config.assertions);
  # 落ちた検査がちょうど1つで、そのメッセージに`fragment`を含むか。
  failsOnlyWith = fragment: result: lib.length result == 1 && lib.hasInfix fragment (lib.head result);

  valid = {
    machineAddresses = {
      outside = {
        host6 = "fdf2:a855:5a3f:100::10";
        guest6 = "fdf2:a855:5a3f:100::11";
        ipv4 = true;
      };
      inside = {
        host6 = "fdf2:a855:5a3f:100::20";
        guest6 = "fdf2:a855:5a3f:100::21";
      };
    };
    machineEgress = {
      outside.internet = true;
    };
  };
  withInside =
    inside:
    valid
    // {
      machineAddresses = valid.machineAddresses // {
        inherit inside;
      };
    };

  validResult = failures valid;
  duplicateResult = failures (withInside {
    host6 = "fdf2:a855:5a3f:100::20";
    # `outside.guest6`の`fdf2:a855:5a3f:100::11`と同じアドレスを省略せずに書いたもの。
    guest6 = "fdf2:a855:5a3f:100:0:0:0:11";
  });
  malformedResult = failures (withInside {
    host6 = "fdf2:a855:5a3f:100::20";
    guest6 = "fdf2:a855:5a3f:100::1a";
  });
  ipv4WithoutInternetResult = failures (
    valid
    // {
      machineEgress = { };
    }
  );
in
assert lib.assertMsg (
  validResult == [ ]
) "正しい宣言で検査が落ちました: ${lib.concatStringsSep "; " validResult}";
assert lib.assertMsg (failsOnlyWith "must be unique" duplicateResult)
  "書き方だけが違う同じアドレスを重複として扱いません: ${lib.concatStringsSep "; " duplicateResult}";
assert lib.assertMsg (failsOnlyWith "must be written as" malformedResult)
  "IPv4を導けない形のアドレスを止めません: ${lib.concatStringsSep "; " malformedResult}";
assert lib.assertMsg (failsOnlyWith "IPv4 is only for" ipv4WithoutInternetResult)
  "インターネットへ出ないマシンのIPv4を止めません: ${lib.concatStringsSep "; " ipv4WithoutInternetResult}";
true
