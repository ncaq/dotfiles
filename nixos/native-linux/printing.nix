{ pkgs, ... }:
{
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      cups-browsed
      cups-filters
      hplip
    ];
  };
}
