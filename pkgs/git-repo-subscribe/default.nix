{
  lib,
  makeWrapper,
  rustPlatform,
  git,
}:
rustPlatform.buildRustPackage {
  pname = "git-repo-subscribe";
  version = "0.1.0";
  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ git ];

  postInstall = ''
    wrapProgram $out/bin/git-repo-subscribe \
      --prefix PATH : ${lib.makeBinPath [ git ]}
  '';

  meta.mainProgram = "git-repo-subscribe";
}
