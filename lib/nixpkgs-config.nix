{ lib, ... }:
let
  # 許可するライセンス。
  allowlistedLicenses = with lib.licenses; [
    nvidiaCudaRedist # 再配布可能ならまだマシ。
    unfreeRedistributable # 再配布可能ならまだマシ。
  ];
  # 明示的に許可するunfreeパッケージのリスト。
  allowedUnfreePackages = [
    "claude-code" # 一番使いやすいLLMエージェントのため仕方がない。
    "discord" # ネイティブ版の方が音声などが安定しているため仕方がない。
    "slack" # ネイティブ版の方が通知などが安定しているため仕方がない。
    "zoom" # ネイティブ版の方が動画などが安定しているため仕方がない。
  ];
  nixpkgsConfig = {
    inherit allowlistedLicenses;
    allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowedUnfreePackages;
  };
in
nixpkgsConfig
