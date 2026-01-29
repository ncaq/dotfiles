_: {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "ssh.forgejo.ncaq.net" = {
        port = 2222;
        extraOptions = {
          # Forgejo's built-in SSH server doesn't support post-quantum key exchange.
          WarnWeakCrypto = "no-pq-kex";
        };
      };
    };
  };
}
