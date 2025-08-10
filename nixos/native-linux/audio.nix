{ pkgs, ... }:
{
  services = {
    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber = {
        enable = true;
        configPackages = [
          (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/51-razer-seiren-mini.conf" ''
            monitor.alsa.rules = [
              {
                matches = [
                  {
                    "node.description" = "~Razer Seiren Mini.*"
                  }
                ]
                actions = {
                  update-props = {
                    "priority.session" = 2100
                    "priority.driver" = 2100
                  }
                }
              }
            ]
          '')
        ];
      };
    };
  };
  # Required by pipewire for realtime process.
  security.rtkit.enable = true;
}
