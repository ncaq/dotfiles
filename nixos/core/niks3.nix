{
  pkgs,
  config,
  inputs,
  ...
}:
let
  inherit (inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}) niks3;
  authTokenPath = config.sops.secrets."niks3-private-client-api-token".path;
in
{
  environment.systemPackages = [ niks3 ];

  nix.settings.post-build-hook = pkgs.lib.getExe (
    pkgs.writeShellApplication {
      name = "niks3-private-push";
      runtimeInputs = [ niks3 ];
      text = ''
        # Nix post-build-hookはOUT_PATHS環境変数でビルド済みストアパスを渡す。
        # pushが失敗してもビルド自体は失敗させない。
        if [ -n "''${OUT_PATHS:-}" ]; then
          niks3 push \
            --server-url "https://seminar.border-saurolophus.ts.net:8443/niks3/private/" \
            --auth-token "$(cat "${authTokenPath}")" \
            "$OUT_PATHS" || echo "niks3-private push failed, ignoring" >&2
        fi
      '';
    }
  );

  sops.secrets."niks3-private-client-api-token" = {
    sopsFile = ../../secrets/niks3-private.yaml;
    key = "api_token";
  };
}
