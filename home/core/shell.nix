{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bc # dcも含まれます。
    jq
    nkf
    parallel
    shellcheck
    xxd
  ];
}
