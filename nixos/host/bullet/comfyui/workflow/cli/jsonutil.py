"""JSONとして読んだ`object`から、期待する形だけを取り出す小道具。

ComfyUIのAPIにも、
`local.comfyui.workflows`が吐くJSONにも型は無い。
`json.loads`が返すのは`object`で、
`isinstance`で絞っても要素の型は不明なままなので、
pyrightのstrictでは毎回`cast`が要る。

同じ`cast`をあちこちに書くと、
どこが「形を確かめている場所」なのかが読めなくなるので、
ここへ集める。

形が合わない時は例外ではなく空を返す。
呼び出し側は欠けていることに気付ける位置で自分の言葉のエラーを投げる。
"""

from typing import cast


def as_object(value: object) -> dict[str, object]:
    """JSONのオブジェクトとして読む。オブジェクトでなければ空。"""
    if not isinstance(value, dict):
        return {}
    return {str(key): item for key, item in cast(dict[object, object], value).items()}


def as_array(value: object) -> list[object]:
    """JSONの配列として読む。配列でなければ空。"""
    if not isinstance(value, list):
        return []
    return list(cast(list[object], value))


def as_text(value: object) -> str:
    """JSONの文字列として読む。文字列でなければ空文字列。

    数値や真偽値を`str()`で文字列に化けさせない。
    ノード型やウィジェット名が数値だったなら、
    それは形が違うのであって、
    たまたま文字列にできることに意味は無い。
    """
    return value if isinstance(value, str) else ""


def as_node_id(value: object) -> str:
    """ノードIDを文字列として読む。

    API形式のノードIDは文字列だが、
    UI形式のJSONでは整数で、
    App Modeの入力定義も整数でノードを指す。
    比較のたびに書き分けると取りこぼすので、
    受け取った時点で文字列へ寄せる。

    `bool`は弾く。
    `isinstance(value, int)`が`True`も通してしまい、
    ノードIDが`"True"`になっても誰も気付けない。
    """
    if isinstance(value, str):
        return value
    if isinstance(value, bool):
        return ""
    if isinstance(value, int):
        return str(value)
    return ""
