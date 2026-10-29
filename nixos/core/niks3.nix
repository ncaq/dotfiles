{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [ inputs.niks3.nixosModules.niks3-auto-upload ];

  services.niks3-auto-upload = {
    enable = true;
    # 公開する側の`nixos/host/seminar/niks3-private.nix`と同じ定義からURLを組み立てる。
    serverUrl = import ../../lib/niks3-private-tailscale-url.nix {
      inherit lib;
      tailnet = config.local.tailscale.tailnet;
    };
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
