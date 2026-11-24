# ユーザがインタラクティブに利用するシェルはzshなのですが、
# いろいろなツールがbashを呼び出すので、
# 最低限の設定を書いておきます。
{
  programs = {
    bash = {
      enable = true;
    };
  };

  home.shell.enableBashIntegration = true;
}
