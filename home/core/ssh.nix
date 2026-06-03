{ pkgs, lib, ... }:
{
  programs.ssh = {
    enable = true;
    package = pkgs.openssh; # システムのがない場合に備えて一貫してインストール指定。
    enableDefaultConfig = false;
    settings = {
      ${
        lib.concatStringsSep " " [
          "bullet"
          "creep"
          "seminar"
          "ssd0086-wsl"
        ]
      } =
        {
          User = "ncaq";
        };
      "ssh.forgejo.ncaq.net" = {
        Port = 2222;
        User = "forgejo";
        # Forgejo's built-in SSH server doesn't support post-quantum key exchange.
        WarnWeakCrypto = "no-pq-kex";
      };
    };
  };
  home.packages = with pkgs; [ mosh ];
}
