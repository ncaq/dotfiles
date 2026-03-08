_: {
  services.snapper = {
    configs = {
      root = {
        SUBVOLUME = "/";

        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
      };
      gideon = {
        SUBVOLUME = "/mnt/gideon";

        TIMELINE_CREATE = false;
        TIMELINE_CLEANUP = true;
      };
      two-thousand = {
        SUBVOLUME = "/mnt/two-thousand";

        TIMELINE_CREATE = false;
        TIMELINE_CLEANUP = true;
      };
    };
  };
}
