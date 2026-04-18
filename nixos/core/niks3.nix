{
  pkgs,
  config,
  inputs,
  ...
}:
{
  imports = [ inputs.niks3.nixosModules.niks3-auto-upload ];

  services.niks3-auto-upload = {
    enable = true;
    serverUrl = "https://seminar.border-saurolophus.ts.net:8443/niks3/private/";
    authTokenFile = config.sops.secrets."niks3-private-client-api-token".path;
  };

  environment.systemPackages = [
    inputs.niks3.packages.${pkgs.stdenv.hostPlatform.system}.niks3
  ];

  sops.secrets."niks3-private-client-api-token" = {
    sopsFile = ../../secrets/niks3-private.yaml;
    key = "api_token";
  };
}
