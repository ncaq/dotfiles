{ pkgs, ... }:
let
  releaseAgeDays = 3;
  isoDuration = "P${toString releaseAgeDays}D";
in
{
  # サプライチェーン攻撃のリスク低減として、
  # PyPI系パッケージマネージャでリリース後3日経過したバージョンをインストールするように設定します。
  # 悪意あるパッケージがpublishされてから検出・取り下げされるまでの猶予を確保する目的です。
  # 各PMで設定キー名・単位・要求バージョンが異なる点に注意。

  programs = {
    # `solver.min-release-age`(単位: 日)。
    poetry = {
      enable = true;
      settings.solver.min-release-age = releaseAgeDays;
    };
    # uvの`exclude-newer`は、
    # RFC 3339、ISO 8601、フレンドリーな期間文字列(`"3 days"`)を受け付けます。
    uv = {
      enable = true;
      settings.exclude-newer = isoDuration;
    };
  };

  # pipの`uploaded-prior-to`(ISO 8601の`P<日数>D`形式のみ)。
  # pipenvやpipxは内部でpipを呼ぶため、
  # pip本体が機能を持てばこれらの経由のインストールにも波及します。
  # pipenvの`cool-down-period`は`Pipfile`内でのみ設定可能で、
  # ユーザグローバル設定の手段が公式には存在しません。
  # pipenv経由の防御はpipの設定に依存する形になります。
  xdg.configFile."pip/pip.conf".text = ''
    [install]
    uploaded-prior-to = ${isoDuration}
  '';

  # グローバルにインストールするPython関連ツール。
  home.packages = with pkgs; [
    black
    isort
    pipenv
    pyright
    python3
    python3Packages.pip
  ];
}
