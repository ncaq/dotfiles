{
  callPackage,
  writeShellApplication,
  coreutils,
  git,
}:
let
  package = writeShellApplication {
    name = "git-repo-subscribe";
    runtimeInputs = [
      coreutils
      git
    ];
    text = builtins.readFile ./git-repo-subscribe.sh;
    passthru.tests = {
      git-repo-subscribe = callPackage ./test.nix {
        git-repo-subscribe = package;
      };
    };
  };
in
package
