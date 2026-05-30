{ pkgs, lib, ... }:
{
  programs.ssh = {
    enable = true;
    package = pkgs.openssh; # システムのがない場合に備えて一貫してインストール指定。
    enableDefaultConfig = false;
    matchBlocks = {
      ${
        lib.concatStringsSep " " [
          "bullet"
          "creep"
          "seminar"
          "ssd0086-wsl"
        ]
      } =
        {
          user = "ncaq";
        };
      "ssh.forgejo.ncaq.net" = {
        port = 2222;
        user = "forgejo";
        extraOptions = {
          # Forgejo's built-in SSH server doesn't support post-quantum key exchange.
          WarnWeakCrypto = "no-pq-kex";
        };
      };
    };
  };
  home.packages = with pkgs; [ mosh ];
}
