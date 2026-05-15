_: {
  programs = {
    ripgrep = {
      enable = true;
      arguments = [
        "--smart-case" # 大文字を含むときだけ大文字小文字を区別します。
        "--search-zip" # zipやjarなどのアーカイブも検索します。
        "--line-number" # 行番号を表示します。
        "--type-not=svg" # SVGはXMLなのでテキスト検索してしまいますが膨大な結果が帰って来るので除外。
        "--hidden" # 隠しファイルも検索。デフォルトでhiddenは`.gitignore'を尊重します。
        "--glob=!.git" # hiddenを有効にすると`.git'も対象になってしまうので避けます。
        "--sort=path" # ソート順を安定させます。
      ];
    };
    ripgrep-all = {
      enable = true;
    };
  };
}
