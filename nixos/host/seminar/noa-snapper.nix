_: {
  services.snapper = {
    configs = {
      noa = {
        SUBVOLUME = "/mnt/noa";
        ALLOW_GROUPS = [ "wheel" ];

        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
      };
    };
  };
}
