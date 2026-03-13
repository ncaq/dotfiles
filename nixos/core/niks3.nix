{
  pkgs,
  config,
  inputs,
  ...
}:
let
  inherit (inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}) niks3;
in
{
  environment.systemPackages = [ niks3 ];

  nix.settings.post-build-hook = pkgs.lib.getExe (
    pkgs.writeShellApplication {
      name = "niks3-private-push";
      runtimeInputs = with pkgs; [
        niks3
        util-linux
      ];
      text = ''
        # Nix post-build-hookはOUT_PATHS環境変数でビルド済みストアパスを渡す。
        # pushが失敗してもビルド自体は失敗させない。
        # Nixデーモンはhookのstdout/stderrをクライアントに転送するため、
        # logger経由でjournalに送ることでターミナルへの出力を抑制する。
        if [ -n "''${OUT_PATHS:-}" ]; then
          NIKS3_AUTH_TOKEN_FILE=${config.sops.secrets."niks3-private-client-api-token".path}
          export NIKS3_AUTH_TOKEN_FILE
          # shellcheck disable=SC2086
          niks3 push \
            --server-url "https://seminar.border-saurolophus.ts.net:8443/niks3/private/" \
            $OUT_PATHS 2>&1 | logger -t niks3-private-push || logger -t niks3-private-push "push failed, ignoring"
        fi
      '';
    }
  );

  sops.secrets."niks3-private-client-api-token" = {
    sopsFile = ../../secrets/niks3-private.yaml;
    key = "api_token";
  };
}
