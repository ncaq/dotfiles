# `secrets/niks3-{public,private}.yaml`からAPIトークンを復号して、
# 自分のniks3サーバに`niks3 push`を実行するラッパー。
# `niks3-push-ncaq-public`と`niks3-push-ncaq-private`の2つのコマンドを提供します。
{
  lib,
  runCommand,
  makeWrapper,
  shellcheck,
  jq,
  niks3,
  sops,
  publicSecretsFile,
  privateSecretsFile,
}:
let
  variants = {
    public = {
      defaultSecretsFile = publicSecretsFile;
      defaultServerUrl = "https://niks3-public.ncaq.net/";
    };
    private = {
      defaultSecretsFile = privateSecretsFile;
      defaultServerUrl = "https://seminar.border-saurolophus.ts.net:8443/niks3/private/";
    };
  };
  runtimePath = lib.makeBinPath [
    jq
    niks3
    sops
  ];
in
runCommand "niks3-push-ncaq"
  {
    nativeBuildInputs = [
      makeWrapper
      shellcheck
    ];
    meta.mainProgram = "niks3-push-ncaq-public";
  }
  ''
    shellcheck ${./niks3-push-ncaq.bash}
    install -Dm755 ${./niks3-push-ncaq.bash} $out/libexec/niks3-push-ncaq/niks3-push-ncaq.bash
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (variant: cfg: ''
        makeWrapper $out/libexec/niks3-push-ncaq/niks3-push-ncaq.bash \
          $out/bin/niks3-push-ncaq-${variant} \
          --set-default NIKS3_PUSH_NCAQ_SECRETS_FILE ${cfg.defaultSecretsFile} \
          --set-default NIKS3_PUSH_NCAQ_SERVER_URL ${lib.escapeShellArg cfg.defaultServerUrl} \
          --prefix PATH : ${runtimePath}
      '') variants
    )}
  ''
