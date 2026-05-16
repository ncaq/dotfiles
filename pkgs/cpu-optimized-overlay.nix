/**
  特定パッケージをCPUモデル固有のCFLAGSで最適化ビルドさせるoverlay。

  `lib/cpu-targets.nix`の`cflagsFor`で得たフラグ群を
  `NIX_CFLAGS_COMPILE`経由で`cc-wrapper`に渡し、
  対象パッケージのビルドに反映する。
  既存derivationと同じ名前で上書きすることで、
  利用側の参照先を変えずに済む。

  `override { stdenv = ...; }`を試して、
  受け付けるパッケージはそちらに切り替えるという案もあったが、
  `pkgs.emacs`のように`override`の形が変則的で、
  `builtins.functionArgs`が通らないケースがあるため、
  全件`overrideAttrs`に統一して安定性を取っている。
*/
cpuName: _final: prev:
let
  cpuTargets = import ../lib/cpu-targets.nix { inherit (prev) lib; };
  flags = cpuTargets.cflagsFor cpuName;

  optimize =
    drv:
    drv.overrideAttrs (old: {
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE =
          toString (old.env.NIX_CFLAGS_COMPILE or "") + " " + builtins.concatStringsSep " " flags;
      };
    });
in
{
  emacs = optimize prev.emacs;
}
