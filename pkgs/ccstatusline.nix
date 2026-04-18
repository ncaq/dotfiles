# ccstatusline - Claude Code CLI用のカスタマイズ可能なstatusline
# https://github.com/sirmalloc/ccstatusline
# npmレジストリからビルド済みパッケージを取得します。
{
  lib,
  stdenv,
  fetchurl,
  nodejs,
  makeWrapper,
}:
stdenv.mkDerivation rec {
  pname = "ccstatusline";
  version = "2.2.7";

  src = fetchurl {
    url = "https://registry.npmjs.org/${pname}/-/${pname}-${version}.tgz";
    hash = "sha256-vMAoLVLSpY+cov1doxX7247c79H+3fQlxUAffYqfD/Q=";
  };

  nativeBuildInputs = [ makeWrapper ];

  unpackPhase = ''
    mkdir -p $out
    tar xzf $src --strip-components=1 -C $out
  '';

  installPhase = ''
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/ccstatusline \
      --add-flags "$out/dist/ccstatusline.js"
  '';

  meta = {
    description = "A customizable status line formatter for Claude Code CLI";
    homepage = "https://github.com/sirmalloc/ccstatusline";
    license = lib.licenses.mit;
    mainProgram = "ccstatusline";
  };
}
