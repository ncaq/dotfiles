_: {
  services.snapper = {
    configs = {
      noa = {
        SUBVOLUME = "/mnt/noa";

        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
      };
    };
  };
}
