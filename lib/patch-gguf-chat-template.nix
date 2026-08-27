/**
  patchGgufChatTemplate: GGUFの`tokenizer.chat_template`へ差分を当てた派生GGUFを作る関数。

  型: { pkgs } -> { gguf, patch } -> derivation

  引数:
    pkgs  - `runCommand`とPythonを取るためのnixpkgs
    gguf  - 元になるGGUF(`fetchHuggingFace`の結果など)
    patch - チャットテンプレートに当てるunified diffのファイル。
            `patch`コマンドがヘッダより前の文章を読み飛ばすので、
            差分の意図はファイルの先頭に書いておける。

  なぜ必要か:
    Hugging Faceで配布されるGGUFのチャットテンプレートには、
    `raise_exception`で入力の形を厳しく検査するものがある。
    コーディングエージェントはuserメッセージ無しの要約リクエストや、
    会話途中のsystemメッセージなど、
    検査に引っ掛かる形を普通に送ってくるため、
    サーバが500を返して使いものにならないことがある。
    そのようなモデルはテンプレートを緩和してから登録する。

  なぜ差分をパッチファイルで与えるか:
    テンプレートは配布元のJinjaで、こちらが変えたいのはその一部でしかない。
    置換前後の文字列の対をNixの文字列で持つ形も試したが、
    インデント文字列が行頭の共通インデントを落とすため、
    Jinjaの深いインデントを再現する規則が直感に反する形になった。
    unified diffなら差分そのものの形で読めて、
    コンテキスト行が配布元のテンプレートの変化を検出する。
    `--fuzz=0`と合わせて、少しでもずれたらビルドが失敗する。

  なぜバイト長を保つか:
    GGUFのメタデータ文字列は長さプレフィックス付きで並んでいるため、
    長さが変わるとそれ以降の全てのオフセットがずれ、
    ファイル全体の書き直しになる。
    `patch_gguf_chat_template.py`が縮んだ分をJinjaのコメントで埋めて長さを揃える。
    伸びる差分は埋めようがないので拒否される。
    その場合は差分の側を短く書き直す。

  なぜreflinkでコピーするか:
    storeがbtrfsのようなreflink対応ファイルシステムなら、
    実際に書き込まれるのは書き換えたメタデータのブロックだけで済む。
    22GB級のGGUFを丸ごと複製せずに派生を作れる。
*/
{ pkgs }:
{
  gguf,
  patch,
}:
pkgs.runCommand "${gguf.name}-patched-template"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    # ネットワークもコンパイルも無いのでリモートビルダーに投げる意味がない。
    preferLocalBuild = true;
    # 出力は数十GBある。
    # 元のGGUFは手元にあるので、substituterから引き直すよりreflinkで作る方が速い。
    allowSubstitutes = false;
  }
  ''
    cp --reflink=auto ${gguf} "$out"
    chmod +w "$out"

    python3 ${./patch_gguf_chat_template.py} extract "$out" chat_template.jinja
    # `--fuzz=0`でコンテキスト行の不一致を許さない。
    # 配布元がテンプレートを変えたらここで失敗する。
    patch --fuzz=0 chat_template.jinja ${patch}
    python3 ${./patch_gguf_chat_template.py} embed "$out" chat_template.jinja
  ''
