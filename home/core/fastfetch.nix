_: {
  programs.fastfetch = {
    enable = true;
    settings = {
      "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json";
      logo = "none";
      modules = [
        "title"
        {
          "type" = "custom";
          "outputColor" = "#FF00FF";
          "format" = "Core Software";
        }
        "os"
        "kernel"
        "bios"
        "bootmgr"
        "initsystem"
        "lm"
        "shell"
        "de"
        "wm"
        "terminal"
        "terminalfont"
        "terminalsize"
        "terminaltheme"
        "locale"
        "users"
        {
          "type" = "custom";
          "outputColor" = "#FF00FF";
          "format" = "Computing";
        }
        "cpu"
        "tpm"
        "gpu"
        "opencl"
        "opengl"
        "vulkan"
        "memory"
        "swap"
        "disk"
        {
          "type" = "custom";
          "outputColor" = "#FF00FF";
          "format" = "Network";
        }
        "localip"
        "dns"
        "wifi"
        "bluetooth"
        "bluetoothradio"
        {
          "type" = "custom";
          "outputColor" = "#FF00FF";
          "format" = "Output";
        }
        "display"
        "brightness"
        "font"
        "sound"
        {
          "type" = "custom";
          "outputColor" = "#FF00FF";
          "format" = "Input";
        }
        "keyboard"
        "mouse"
        "camera"
        "gamepad"
        {
          "type" = "custom";
          "outputColor" = "#FF00FF";
          "format" = "Core Hardware";
        }
        "host"
        "board"
        {
          "type" = "custom";
          "outputColor" = "#FF00FF";
          "format" = "Current State";
        }
        "battery"
        "poweradapter"
        "datetime"
        "uptime"
      ];
    };
  };
}
