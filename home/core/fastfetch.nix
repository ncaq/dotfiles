_: {
  programs.fastfetch = {
    enable = true;
    settings = {
      "$schema" = "https://github.com/fastfetch-cli/fastfetch/raw/master/doc/json_schema.json";
      logo = "none";
      modules = [
        "title"
        "os"
        "host"
        "board"
        "kernel"
        "bios"
        "bootmgr"
        "initsystem"
        "lm"
        "shell"
        "display"
        "de"
        "wm"
        "wmtheme"
        "terminal"
        "terminalfont"
        "terminalsize"
        "terminaltheme"
        "cpu"
        "cpucache"
        "cpuusage"
        "gpu"
        "disk"
        "memory"
        "swap"
        "battery"
        "bluetooth"
        "bluetoothradio"
        "brightness"
        "camera"
        "dns"
        "font"
        "gamepad"
        "keyboard"
        "locale"
        "localip"
        "mouse"
        "opencl"
        "opengl"
        "vulkan"
        "sound"
        "tpm"
        "uptime"
        "users"
        "wifi"
      ];
    };
  };
}
