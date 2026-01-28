_: {
  services.caddy = {
    enable = true;
    email = "ncaq@ncaq.net";
    virtualHosts."seminar.border-saurolophus.ts.net".extraConfig = ''
      respond "Hello from seminar!"
    '';
  };
}
