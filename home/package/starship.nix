{ ... }:
{
  programs.starship = {
    enable = true;

    settings = {
      directory = {
        truncation_length = 100;
        truncate_to_repo = false;
      };

      status = {
        disabled = false;
        format = "[\\[$symbol $common_meaning $signal_name $int\\]]($style) ";
      };

      time = {
        disabled = false;
        format = "[$time]($style) ";
        time_format = "%Y-%m-%dT%H:%M:%S";
      };
    };
  };
}
