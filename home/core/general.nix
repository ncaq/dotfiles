{ pkgs, ... }:
{
  home.packages = with pkgs; [
    attic-client
    bc # dcも含まれます。
    cachix
    jq
    license-generator
    nkf
    openssl
    parallel
    plantuml
    rakudo
    shellcheck
    sqlite
    strace
    trashy
    xxd
  ];
}
