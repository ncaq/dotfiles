{ pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    # gccを優先。`cc`, `c++`コマンドはgccのものになる。
    (lib.hiPrio gcc)
    (lib.lowPrio clang)

    ccls
    cmake
    gdb
    libgcc
    libgccjit
    libllvm
    lldb
  ];
}
