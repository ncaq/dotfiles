{ ... }:
{
  services.snapper = {
    configs = {
      root = {
        SUBVOLUME = "/";
        ALLOW_GROUPS = [ "wheel" ];

        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
      };
    };
  };
}
