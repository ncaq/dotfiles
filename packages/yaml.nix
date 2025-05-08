{ pkgs, ... }:
let
  yamlFormat = pkgs.formats.yaml { };

  yamllintConfig = {
    extends = "default";
    rules = {
      # デフォルトの行数制限は厳しすぎるので緩和
      line-length = {
        max = 200;
        level = "warning";
      };
      # スタート記号を省略を許可
      document-start = "disable";
      # GitHub Actionsなどで頻出するので単純キーを許可する
      truthy = "disable";
      # prettierと競合しない設定にする
      comments = {
        min-spaces-from-content = 1;
      };
    };
  };
in
{
  home.packages = with pkgs; [
    yamllint
  ];

  xdg.configFile."yamllint/config".source = yamlFormat.generate "yamllint-config" yamllintConfig;
}
