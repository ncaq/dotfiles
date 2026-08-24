"""`{a|b|c}`から1つ選ぶ動的プロンプトを展開する。

ComfyUIのUIでは、
`{standing|sitting|walking}`と書いておくと、
キューへ入れる時に1つが選ばれます。
1つのプロンプトから毎回違う絵を出すための仕組みである。

これを展開しているのはフロントエンドである。
`extensions/core/dynamicPrompts.ts`が、
`dynamicPrompts`を持つウィジェットの`serializeValue`を差し替えて、
`graphToPrompt`が値を読む瞬間に置き換える。
サーバ側にこの処理は無い。

つまりフロントエンドを通らないこのコマンドは、
何もしなければ`{a|b|c}`という文字列をそのままモデルへ送る。
UIで書いたワークフローをコマンドから投げた時に、
同じ入力から違う結果が出るということなので、
変換の取りこぼしとして直す。

# 本家との違い

選択を`--seed`から決める。
本家は`Math.random`なので、
同じワークフローを同じseedで投げても選択が揃わない。
こちらはseedを固定すれば選択も揃うので、
気に入った1枚を後から作り直せる。

決め方には擬似乱数の列ではなくハッシュ関数を使う。

`random.Random(seed)`から順に引くと、
あるブロックの選択が「そこまでに何個引いたか」に依存する。
プロンプトの先頭へ選択肢を1つ足しただけで、
後ろのブロックの選択が全部ずれてしまう。
気に入った1枚に候補を足して試す、という使い方ができない。

seedとブロックの中身からインデックスを直接求めれば、
ブロック同士が独立する。
欲しいのは擬似乱数の列ではなく、
鍵から値を引く関数の方だった。

同じ中身のブロックを2つ書いた時のために出現回数も鍵へ入れる。
ポジティブとネガティブに同じ選択肢を書いた時のために、
どのウィジェットかも入れる。

波括弧を含まない値には触らない。
本家は`dynamicPrompts`を持つウィジェットの値を常に通すので、
`//`や`/* */`がコメントとして消える。
プロンプトにその並びが出る事故は稀だが、
選択肢を書いていない人が黙って文字を失うのは避ける。
"""

import hashlib
import re
from dataclasses import dataclass, field

from convert import Prompt
from nodedef import NodeDef

# C言語風のコメント。本家の`stripComments`と同じものを落とす。
COMMENT = re.compile(r"/\*[\s\S]*?\*/|//.*")

# 展開し終わった後に外すエスケープ。
# 波括弧と縦棒だけが対象で、
# `yuuka \(blue_archive\)`のような他のエスケープはそのまま残る。
ESCAPED_SYNTAX = re.compile(r"\\([{}|])")


@dataclass
class Chooser:
    """seedとブロックの中身から選択肢のインデックスを決める。

    `seen`は同じ中身のブロックが何度目かを数える。
    `{a|b}`を2つ並べた時に、
    鍵が同じになって必ず揃ってしまうのを防ぐ。
    """

    seed: int
    # どのウィジェットの値かを表す文字列。
    # ポジティブとネガティブに同じ選択肢を書いた時に、
    # 別々に引かせるために鍵へ混ぜる。
    salt: str
    seen: dict[str, int] = field(default_factory=dict[str, int])

    def index(self, body: str, count: int) -> int:
        """このブロックで選ぶ選択肢の位置を返す。"""
        occurrence = self.seen.get(body, 0)
        self.seen[body] = occurrence + 1
        # 区切りにNULを使う。
        # プロンプトにNULは書けないので、
        # 中身と出現回数の境目が中身の側の文字と紛れない。
        key = f"{self.seed}\0{self.salt}\0{body}\0{occurrence}".encode()
        digest = hashlib.blake2b(key, digest_size=8).digest()
        # 剰余の偏りは`count`が2^64に対して極端に小さいので無視できる。
        # 選択肢が数個から数十個の話で、偏りの比は10^-18の桁になる。
        return int.from_bytes(digest, "big") % count


def _escape(text: str, index: int) -> tuple[str, int]:
    """バックスラッシュとその次の1文字を、意味を解釈せずに持ち越す。"""
    if len(text) <= index:
        return ("\\", index)
    return ("\\" + text[index], index + 1)


def _choose(text: str, index: int, chooser: Chooser) -> tuple[str, int]:
    """`{`の次から`}`までを読み、選んだ1つを返す。

    入れ子は深さで数える。
    深さ0の`|`だけが選択肢の区切りで、
    内側の`|`は選択肢の一部として持ち越す。
    """
    options: list[str] = []
    choice = ""
    depth = 0
    while index < len(text):
        char = text[index]
        index += 1
        if char == "\\":
            chunk, index = _escape(text, index)
            choice += chunk
            continue
        if char == "{":
            depth += 1
        elif char == "}":
            if depth == 0:
                break
            depth -= 1
        elif char == "|" and depth == 0:
            options.append(choice)
            choice = ""
            continue
        choice += char
    options.append(choice)
    # 深さ0の`|`でしか切っていないので、繋ぎ直せば波括弧の中身がそのまま戻る。
    # それをブロックの識別に使う。
    body = "|".join(options)
    # 選んだものの中にまだ選択肢が残っていることがあるので、そちらも展開する。
    return (_expand(options[chooser.index(body, len(options))], chooser), index)


def _expand(text: str, chooser: Chooser) -> str:
    """走査して、波括弧を選んだ1つへ置き換える。

    コメントの除去と最後のエスケープ外しは`expand`が1度だけ行う。
    本家は入れ子のたびに全体の処理をやり直すが、
    同じ文字列を二度コメント除去しても結果は変わらず、
    エスケープを内側で先に外すと外側の判断が変わりうる。
    """
    result = ""
    index = 0
    while index < len(text):
        char = text[index]
        index += 1
        if char == "\\":
            chunk, index = _escape(text, index)
            result += chunk
            continue
        if char == "{":
            chunk, index = _choose(text, index, chooser)
            result += chunk
            continue
        result += char
    return result


def expand(text: str, seed: int, salt: str = "") -> str:
    """動的プロンプトを展開する。"""
    return ESCAPED_SYNTAX.sub(
        r"\1", _expand(COMMENT.sub("", text), Chooser(seed=seed, salt=salt))
    )


def sources(
    prompt: Prompt, node_defs: dict[str, NodeDef]
) -> dict[tuple[str, str], str]:
    """展開の対象になる値を、ノードIDとウィジェット名から引ける形で集める。

    展開の前に集めておくのは、
    `--repeat`で複数回投げる時に毎回選び直すためである。
    書き換えた後の値には選択肢が残っていないので、
    展開後の値から展開し直すことはできない。
    """
    found: dict[tuple[str, str], str] = {}
    for node_id, node in prompt.nodes.items():
        definition = node_defs.get(node.class_type)
        if definition is None:
            continue
        for name, value in node.inputs.items():
            widget = definition.widget(name)
            if widget is None or not widget.dynamic:
                continue
            if isinstance(value, str) and "{" in value:
                found[(node_id, name)] = value
    return found


def expand_into(
    prompt: Prompt, found: dict[tuple[str, str], str], seed: int
) -> dict[str, str]:
    """集めた値を展開してプロンプトへ書き戻し、書き戻した内容を返す。"""
    applied: dict[str, str] = {}
    for (node_id, name), text in found.items():
        target = f"{node_id}.{name}"
        expanded = expand(text, seed, salt=target)
        prompt.nodes[node_id].inputs[name] = expanded
        applied[target] = expanded
    return applied
