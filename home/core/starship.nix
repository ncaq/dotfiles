_: {
  programs.starship = {
    enable = true;

    settings = {
      # 2行で表示する。
      # 1行目には情報をあるだけたくさん表示する。
      # 2行目にはDebian風のシンプルなプロンプトを表示する。
      # 2行目をシンプルにしているのは、他の人やLLMに例示する時に誤解されにくいようにするため。
      format = "$time$all\n$username$hostname$directory$character";
      line_break = {
        # allの中に含まれてしまっているので、
        # 自分で改行を制御するために無効化します。
        disabled = true;
      };
      time = {
        format = "[$time]($style) ";
        time_format = "%Y-%m-%dT%H:%M:%S";
        disabled = false;
      };
      status = {
        disabled = false;
        map_symbol = true;
        pipestatus = true;
      };
      username = {
        format = "[$user]($style)@";
        show_always = true;
      };
      hostname = {
        ssh_only = false;
        format = "[$ssh_symbol$hostname]($style):";
      };
      directory = {
        truncation_length = 100;
        truncate_to_repo = false;
      };
    };
  };
}
