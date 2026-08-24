"""App Modeの入力定義から、コマンドラインのパラメータを決める。

ノードIDで指すのをやめたい、というのがこの仕組みの出発点である。
ではノードIDの代わりに何で指すのかというと、
ワークフローが既に持っているものがある。

UI形式の`extra.linearData.inputs`がそれで、
`[ノードID, ウィジェット名]`の並びとして、
そのワークフローで人が触る値だけを列挙している。
ComfyUIのApp Modeが画面へ並べるのに使う定義で、
`workflow/lib/widget.nix`がウィジェット名の妥当性を評価時に検査している。

つまり「どれが入力か」は宣言済みで、
外から呼べる場所に置かれていなかっただけである。

# 名前の衝突

ウィジェット名をそのままフラグにすると衝突する。
`anima-standard`はポジティブとネガティブの両方が`CLIPTextEncode`の`text`で、
どちらも`--text`になってしまう。

衝突したものだけノードのタイトルへ譲る。
`Positive Prompt`と`Negative Prompt`という表示名が既に付いているので、
`--positive-prompt`と`--negative-prompt`になる。

タイトルが日本語だとASCIIの名前を作れないので、
その場合はノードIDまで落ちる。
落ちてもフラグ名は`--help`に出るので、
読めば分かる状態は保たれる。

# seedを外す理由

`seed`と`noise_seed`はパラメータにしない。
UIで`randomize`にしてあるseedを振り直しているのはフロントエンドなので、
APIから投げると書かれた値のまま固まる。
`anima-standard`のようにサンプラーが3つあるワークフローでは、
その全てを揃って動かしたい。
1つのノードのseedだけを指すフラグは用途に合わないので、
`main.py`が持つ全体のオプションへ寄せる。
"""

import re
from collections import Counter
from dataclasses import dataclass

from convert import Prompt
from jsonutil import as_array, as_node_id, as_object, as_text
from nodedef import SEED_WIDGET_NAMES, NodeDef, Widget


# 予約された名前が1つも無いことを表す既定値。
# `frozenset()`を引数の既定値へ直接書くと、
# 既定値の中の関数呼び出しとしてpyrightが止める。
NO_RESERVED_FLAGS: frozenset[str] = frozenset()


@dataclass(frozen=True)
class Parameter:
    """コマンドラインのフラグ1つと、それが書き換える先。"""

    # フラグ名。先頭の`--`は含まない。
    name: str
    node_id: str
    widget: Widget
    # `--help`へ出す説明。App Modeの入力定義が持っていれば使う。
    description: str
    # 何も指定しなかった場合に使われる、ワークフローに書かれている値。
    default: object


def slug(text: str) -> str:
    """フラグに使えるASCIIの名前へ落とす。作れなければ空文字列。

    英字で始まらないものは作れなかったものとして扱う。
    `参考画像2`のようなタイトルからは`2`しか残らず、
    `--2`というフラグはargparseが負の数と区別できずに壊れる。
    """
    name = "-".join(part.lower() for part in re.findall(r"[A-Za-z0-9]+", text))
    return name if name[:1].isalpha() else ""


def _candidates(node_id: str, title: str, widget: str) -> list[str]:
    """そのパラメータに使える名前を、望ましい順に並べる。"""
    names = [
        slug(widget),
        slug(title),
        f"{slug(title)}-{slug(widget)}",
        f"node{node_id}-{slug(widget)}",
    ]
    # 前と同じものと、名前を作れなかったものを落とす。
    unique: list[str] = []
    for name in names:
        if name and name not in unique and not name.startswith("-"):
            unique.append(name)
    return unique


def resolve_names(
    candidates: list[list[str]], reserved: frozenset[str] = NO_RESERVED_FLAGS
) -> list[str]:
    """候補の並びから、重複しないフラグ名を決める。

    望ましい順に見て、
    その段で1つしか名乗り手のいない名前だけを確定させる。
    衝突したものは次の段へ持ち越す。

    `reserved`は`--seed`のような全体のオプションが先に取っている名前で、
    最初から使用済みとして扱う。
    パラメータ側に譲らせるのは、
    ワークフローが増えるたびに全体のオプションの名前が変わる方が困るからである。

    候補の末尾にはノードIDを含む名前があるので、
    普通はそこで分かれる。

    それでも決まらないのは、
    同じノードの同じウィジェットを2度書いた場合だけである。
    その場合は`unnamed`に位置を付けた名前へ落とす。
    どちらを採っても書き込む先は同じなので、
    名前が読めることより重複しないことを優先する。
    """
    resolved: list[str | None] = [None] * len(candidates)
    taken: set[str] = set(reserved)
    depth = max((len(names) for names in candidates), default=0)
    for level in range(depth):
        pending = [
            index
            for index, names in enumerate(candidates)
            if resolved[index] is None and level < len(names)
        ]
        counts = Counter(candidates[index][level] for index in pending)
        for index in pending:
            name = candidates[index][level]
            if counts[name] == 1 and name not in taken:
                resolved[index] = name
                taken.add(name)
    return [
        name if name is not None else f"unnamed{index}"
        for index, name in enumerate(resolved)
    ]


def parameters(
    workflow: object,
    prompt: Prompt,
    node_defs: dict[str, NodeDef],
    reserved: frozenset[str] = NO_RESERVED_FLAGS,
) -> list[Parameter]:
    """App Modeの入力定義からパラメータの一覧を組み立てる。"""
    linear = as_object(as_object(as_object(workflow).get("extra")).get("linearData"))
    entries: list[tuple[str, Widget, str, object]] = []
    candidates: list[list[str]] = []
    for raw in as_array(linear.get("inputs")):
        entry = as_array(raw)
        if len(entry) < 2:
            continue
        node_id = as_node_id(entry[0])
        widget_name = as_text(entry[1])
        if widget_name in SEED_WIDGET_NAMES:
            continue
        node = prompt.nodes.get(node_id)
        if node is None:
            raise ValueError(f"App Mode入力が存在しないノード{node_id}を指しています")
        definition = node_defs.get(node.class_type)
        widget = definition.widget(widget_name) if definition is not None else None
        if widget is None:
            raise ValueError(
                f"ノード{node_id}({node.class_type})に{widget_name}がありません"
            )
        config = as_object(entry[2]) if 2 < len(entry) else {}
        entries.append(
            (
                node_id,
                widget,
                as_text(config.get("description")),
                node.inputs.get(widget_name),
            )
        )
        candidates.append(_candidates(node_id, node.title, widget_name))
    return [
        Parameter(
            name=name,
            node_id=node_id,
            widget=widget,
            description=description,
            default=default,
        )
        for name, (node_id, widget, description, default) in zip(
            resolve_names(candidates, reserved), entries, strict=True
        )
    ]


def apply(prompt: Prompt, parameter: Parameter, value: object) -> None:
    """パラメータの値をプロンプトへ書き込む。"""
    prompt.nodes[parameter.node_id].inputs[parameter.widget.name] = value


def apply_seed(prompt: Prompt, seed: int) -> list[str]:
    """振り直される約束だったウィジェットへseedを配り、配った先を返す。

    `fixed`と書かれているものは触らない。
    UIで意図して固定したものが、
    APIから投げた時だけ動くのはおかしい。
    """
    applied: list[str] = []
    for node_id, controls in prompt.controls.items():
        for widget_name, control in controls.items():
            if control == "fixed":
                continue
            prompt.nodes[node_id].inputs[widget_name] = seed
            applied.append(f"{node_id}.{widget_name}")
    return applied
