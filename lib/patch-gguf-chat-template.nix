# GGUFの`tokenizer.chat_template`へ文字列置換を適用した派生GGUFを作る共通関数。
#
# Hugging Faceで配布されるGGUFのチャットテンプレートには、
# `raise_exception`で入力の形を厳しく検査するものがある。
# コーディングエージェントはuserメッセージ無しの要約リクエストや、
# 会話途中のsystemメッセージなど検査に引っ掛かる形を普通に送ってくるため、
# サーバが500を返して使いものにならないことがある。
# そのようなモデルはテンプレートの該当箇所を置換して緩和してから登録する。
#
# GGUFのメタデータ文字列は長さプレフィックス付きで、
# 長さが変わるとファイル全体の書き直しになるため、
# 置換はバイト長を維持する(縮んだ分はJinjaコメントでパディングされる)。
# 伸びる置換はスクリプトが拒否するので、
# その場合は置換後の記述を短く書き直す必要がある。
#
# `cp --reflink=auto`でコピーしてからin-placeで書き換えるので、
# storeがbtrfsのようなreflink対応ファイルシステムなら、
# 数十GBのGGUFでも実際に書き込まれるのは変更したメタデータ部分だけで済む。
{ pkgs }:
let
  inherit (pkgs) lib;
in
{
  # 元になるGGUF(`fetchHuggingFace`の結果など)。
  gguf,
  # `[{ from = "..."; to = "..."; }]`のリスト。
  # 各`from`はテンプレート中にちょうど1回現れる必要がある。
  replacements,
}:
pkgs.runCommand "${gguf.name or (baseNameOf gguf)}-patched-template"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    replacementsJson = builtins.toJSON replacements;
    passAsFile = [ "replacementsJson" ];
    # ネットワークもコンパイルも無いのでリモートビルダーに投げる意味がない。
    preferLocalBuild = true;
  }
  ''
    cp --reflink=auto ${lib.escapeShellArg gguf} "$out"
    chmod +w "$out"
    python3 ${./patch-gguf-chat-template.py} "$out" "$replacementsJsonPath"
  ''
