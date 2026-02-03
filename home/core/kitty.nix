{ pkgs, osConfig, ... }:
let
  kitty-wrapper = pkgs.writeShellScriptBin "kitty-wrapper" ''
    if command -v kitty >/dev/null 2>&1; then
      exec kitty "$@"
    else
      echo "kitty not found in system PATH. Please install kitty via your system package manager." >&2
      exit 1
    fi
  '';
in
{
  # tmuxに任せられるところは任せます。
  programs.kitty = {
    enable = true;

    # 非NixOS環境だとOpenGLの問題があるため、システムのパッケージを使う。
    package = if osConfig == null then kitty-wrapper else pkgs.kitty;

    settings = {
      font_size = 12;

      tab_bar_min_tabs = 0;
      tab_title_template = "[{index}]{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{title}";

      confirm_os_window_close = 0;

      macos_option_as_alt = "yes";
    };

    keybindings = { };

    extraConfig = ''
      mouse_map left click ungrabbed no-op
      mouse_map ctrl+left click ungrabbed mouse_handle_click selection link prompt
      mouse_map ctrl+left press ungrabbed mouse_selection normal
    '';
  };
}
