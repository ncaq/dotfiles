{
  runCommand,
  coreutils,
  git,
  git-repo-subscribe,
}:
runCommand "git-repo-subscribe-test"
  {
    nativeBuildInputs = [
      coreutils
      git
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    bash ${./test.sh} ${git-repo-subscribe}/bin/git-repo-subscribe
    touch "$out"
  ''
