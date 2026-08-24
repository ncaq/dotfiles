"""ComfyUIの`/object_info`から、ワークフローの解釈に必要な部分だけを取り出す。

UI形式のワークフローは、
ノードのウィジェットの値を`widgets_values`という名前の無い配列で持つ。
API形式は同じものを名前付きの`inputs`で持つ。
つまり変換には「この配列の何番目が何という名前なのか」が要る。
それを知っているのはノードの定義だけで、
定義を返すのが`/object_info`である。

このモジュールは配列の並びを`Slot`のタプルとして組み立てる。
`Slot.widget`がNoneのものは、
ノード定義には無いのにフロントエンドが足すウィジェットで、
配列の位置だけを占めてAPIへは送られない。

# フロントエンドが足すもの

`control_after_generate`が代表である。
seedの隣に並ぶ`fixed`や`randomize`がそれで、
`addValueControlWidget`が`serialize: false`で作るため、
`widgets_values`には残るがAPIのプロンプトには入らない。
付く条件はフロントエンドの`useIntWidget.ts`にあり、
入力定義の`control_after_generate`か、
名前が`seed`か`noise_seed`かのどちらかである。

画像や動画のアップロードボタンも同じく位置を占める。
こちらは入力定義の`image_upload`や`video_upload`から分かる。

これらは値の有無が揺れる。
`LoadVideo`は`example.mp4`と`image`の2つを持つワークフローもあれば、
ファイル名だけの1つで書かれているものもある。
そのため位置合わせは厳密な長さ一致ではなく、
名前の付いたスロットを優先して埋める形にしてある。
"""

from dataclasses import dataclass

from jsonutil import as_array, as_object, as_text

# ウィジェットとして描かれる入力の型。
# MODELやIMAGEのようにソケットでしか繋げないものはここに無く、
# `widgets_values`の位置も占めない。
WIDGET_SCALAR_TYPES = frozenset({"INT", "FLOAT", "STRING", "BOOLEAN", "COMBO"})

# フロントエンドが`control_after_generate`を勝手に足す名前。
# 入力定義が明示していなくても付く。
SEED_WIDGET_NAMES = frozenset({"seed", "noise_seed"})

# ノード定義から並びを導けないノード型のスロット。
#
# カスタムノードがJavaScriptの拡張でウィジェットを足すと、
# `/object_info`には現れないのに`widgets_values`の位置は占める。
# 定義から導けない以上、ここへ書き写すしかない。
#
# Noneはフロントエンドだけのスロットで、値を捨てる位置を表す。
#
# 長さが合わなくなれば`convert.py`が例外で止まるので、
# 上流が変わった時に黙って別の値がAPIへ流れることはない。
FRONTEND_WIDGET_SLOTS: dict[str, tuple[str | None, ...]] = {
    # LoRA Managerの`Lora Loader (LoraManager)`。
    # 先頭がテキスト補完のメタデータ、末尾が適用中のLoRAの一覧で、
    # どちらもLoRA Managerの拡張が描いている。
    # ノード定義が持つのは真ん中の`text`だけである。
    "Lora Loader (LoraManager)": (None, "text", None),
}


@dataclass(frozen=True)
class Widget:
    """APIの`inputs`へ名前付きで送るウィジェット1つ。"""

    name: str
    # `WIDGET_SCALAR_TYPES`のいずれか。
    # ノード定義がソケット用の型を書いているのにフロントエンドが描くものは、
    # `FRONTEND_WIDGET_SLOTS`が拾うのでSTRINGとして扱う。
    kind: str
    # COMBOの選択肢。それ以外はNone。
    choices: tuple[str, ...] | None


@dataclass(frozen=True)
class Slot:
    """`widgets_values`の位置1つ分。"""

    # Noneならフロントエンドだけのスロットで、APIへは送らない。
    widget: Widget | None
    # `control_after_generate`のスロットなら、それが操作するウィジェット名。
    controls: str | None


@dataclass(frozen=True)
class NodeDef:
    """1つのノード型について、変換に要るものだけ。"""

    slots: tuple[Slot, ...]
    # 必須入力の名前。変換の結果が埋まっているかを確かめるために持つ。
    required: tuple[str, ...]

    def widget(self, name: str) -> Widget | None:
        """名前からウィジェットを引く。無ければNone。"""
        for slot in self.slots:
            if slot.widget is not None and slot.widget.name == name:
                return slot.widget
        return None


def _widget_of(name: str, spec: object) -> tuple[Widget | None, dict[str, object]]:
    """入力定義1つを読んで、ウィジェットならそれと、常にオプションを返す。

    定義は`[型, オプション]`の配列である。
    型が配列そのものならCOMBOの選択肢を直接書いた古い形で、
    文字列の`"COMBO"`ならオプションの`options`に選択肢が入る新しい形になる。
    どちらも現役なので両方読む。
    """
    entry = as_array(spec)
    if not entry:
        return (None, {})
    kind = entry[0]
    options = as_object(entry[1]) if 1 < len(entry) else {}
    if isinstance(kind, list):
        # 絞り込んだ`kind`ではなく元の要素を渡す。
        # `isinstance`が返す`list`は要素の型が不明なままで、
        # そのまま渡すとpyrightがstrictで通さない。
        choices = tuple(as_text(choice) for choice in as_array(entry[0]))
        return (Widget(name=name, kind="COMBO", choices=choices), options)
    if kind == "COMBO":
        choices = tuple(as_text(choice) for choice in as_array(options.get("options")))
        return (Widget(name=name, kind="COMBO", choices=choices), options)
    if isinstance(kind, str) and kind in WIDGET_SCALAR_TYPES:
        return (Widget(name=name, kind=kind, choices=None), options)
    return (None, options)


def _input_names(definition: dict[str, object], group: str) -> list[str]:
    """入力の名前を定義順に並べる。

    `input_order`が定義順の正本である。
    `input`の側は辞書なので、
    Pythonの挿入順に依存せずに済むよう`input_order`を優先する。
    """
    order = as_object(definition.get("input_order"))
    names = [as_text(name) for name in as_array(order.get(group))]
    if names:
        return [name for name in names if name]
    return list(as_object(as_object(definition.get("input")).get(group)))


def _declared_slots(definition: dict[str, object]) -> tuple[Slot, ...]:
    """ノード定義からスロットの並びを組み立てる。"""
    spec = as_object(definition.get("input"))
    slots: list[Slot] = []
    for group in ("required", "optional"):
        entries = as_object(spec.get(group))
        for name in _input_names(definition, group):
            widget, options = _widget_of(name, entries.get(name))
            # `forceInput`はウィジェットで描けるものをソケットとして描かせる。
            # 位置を占めないので、ここで落とさないと以降が全てずれる。
            if widget is None or options.get("forceInput"):
                continue
            slots.append(Slot(widget=widget, controls=None))
            if options.get("control_after_generate", name in SEED_WIDGET_NAMES):
                slots.append(Slot(widget=None, controls=name))
            if any(key.endswith("_upload") and value for key, value in options.items()):
                slots.append(Slot(widget=None, controls=None))
    return tuple(slots)


def _overridden_slots(
    definition: dict[str, object], names: tuple[str | None, ...]
) -> tuple[Slot, ...]:
    """`FRONTEND_WIDGET_SLOTS`の並びからスロットを組み立てる。

    名前の付いた位置は、
    ノード定義に同じ名前の入力があればその型を使う。
    無い型で描かれている場合はSTRINGとして扱う。
    ここへ書き写す必要が出るのは定義から型が読めない時なので、
    読めないことの方が普通である。
    """
    spec = as_object(definition.get("input"))
    slots: list[Slot] = []
    for name in names:
        if name is None:
            slots.append(Slot(widget=None, controls=None))
            continue
        entry: object = None
        for group in ("required", "optional"):
            found = as_object(spec.get(group)).get(name)
            if found is not None:
                entry = found
        widget, _ = _widget_of(name, entry)
        slots.append(
            Slot(
                widget=widget or Widget(name=name, kind="STRING", choices=None),
                controls=None,
            )
        )
    return tuple(slots)


def parse(parsed: object) -> dict[str, NodeDef]:
    """`/object_info`の応答をノード型ごとの定義へ変換する。"""
    definitions = as_object(parsed)
    if not definitions:
        raise ValueError("/object_infoがオブジェクトを返しませんでした")
    node_defs: dict[str, NodeDef] = {}
    for class_type, raw in definitions.items():
        definition = as_object(raw)
        override = FRONTEND_WIDGET_SLOTS.get(class_type)
        node_defs[class_type] = NodeDef(
            slots=(
                _overridden_slots(definition, override)
                if override is not None
                else _declared_slots(definition)
            ),
            required=tuple(_input_names(definition, "required")),
        )
    return node_defs
