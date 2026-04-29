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
          "key" = "Core Software";
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
          "key" = "Computing";
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
          "key" = "Network";
        }
        "localip"
        "dns"
        "wifi"
        "bluetooth"
        "bluetoothradio"
        {
          "type" = "custom";
          "key" = "Output";
        }
        "display"
        "brightness"
        "font"
        "sound"
        {
          "type" = "custom";
          "key" = "Input";
        }
        "keyboard"
        "mouse"
        "camera"
        "gamepad"
        {
          "type" = "custom";
          "key" = "Core Hardware";
        }
        "host"
        "board"
        {
          "type" = "custom";
          "key" = "Current State";
        }
        "battery"
        "poweradapter"
        "datetime"
        "uptime"
      ];
    };
  };
}
