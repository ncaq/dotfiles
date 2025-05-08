{ ... }:
{
  programs.kitty = {
    enable = true;

    settings = {
      font_size = 12;

      scrollback_lines = 100000;
      scrollback_pager_history_size = 10;

      tab_bar_min_tabs = 0;
      tab_title_template = "[{index}]{fmt.fg.red}{bell_symbol}{activity_symbol}{fmt.fg.tab}{title}";

      confirm_os_window_close = 2;

      macos_option_as_alt = "yes";
    };

    keybindings = {
      "ctrl+o" = "new_tab_with_cwd";
      "ctrl+q" = "close_tab";
      "ctrl+alt+s" = "move_tab_forward";
      "ctrl+alt+h" = "move_tab_backward";
    };

    extraConfig = ''
      mouse_map left click ungrabbed no-op
      mouse_map ctrl+left click ungrabbed mouse_handle_click selection link prompt
      mouse_map ctrl+left press ungrabbed mouse_selection normal
      mouse_map shift+up scroll_line_up
      mouse_map shift+down scroll_line_down
      mouse_map shift+left scroll_page_up
      mouse_map shift+right scroll_page_down
    '';

    shellIntegration = {
      enableBashIntegration = true;
      enableZshIntegration = true;
    };
  };
}
