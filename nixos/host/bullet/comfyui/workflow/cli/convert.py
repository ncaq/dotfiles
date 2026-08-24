"""UI形式のワークフローをAPI形式のプロンプトへ変換する。

ComfyUIのワークフローには2つの形がある。
UI形式は画面に描くための形で、
ノードの位置も、リンクの一覧も、ウィジェットの値の並びも持つ。
API形式は`POST /prompt`が受け取る形で、
ノードIDから`class_type`と名前付きの`inputs`への辞書でしかない。

`local.comfyui.workflows`が持っているのはUI形式だけである。
ComfyUIのサーバ側に変換は無く、
`graphToPrompt`はフロントエンドのJavaScriptの中にしかない。

このモジュールはその`graphToPrompt`のうち、
静的なワークフローに要る部分だけを書き写したものである。
やることは2つに尽きる。

- `widgets_values`の値へ、ノード定義から取った名前を付ける
- `links`を辿って、繋がっている入力を`[ノードID, 出力スロット]`へ直す

# 何を捨てるか

`Note`のような画面にしか存在しないノードは落とす。
フロントエンドでは`isVirtualNode`が真のもので、
`class_type`に対応する実装がサーバ側に無い。

`control_after_generate`のようにフロントエンドが足したウィジェットも落とす。
判断は`nodedef.py`が持っていて、
ここは`Slot.widget`がNoneかどうかだけを見る。

# 何を残すか

`control_after_generate`の値そのものは`Prompt.controls`へ残す。
UIで`randomize`にしてあるseedは、
APIから同じワークフローを投げると毎回同じ値のままになる。
乱数を振り直しているのはフロントエンドだからで、
サーバ側は書かれた値をそのまま使う。
何も知らずに投げると同じ画像が出続けるので、
どのウィジェットが振り直される約束だったのかを呼び出し側へ渡す。
"""

from dataclasses import dataclass, field

from jsonutil import as_array, as_node_id, as_object, as_text
from nodedef import NodeDef, Slot

# 画面にしか存在せず、サーバ側に実装を持たないノード型。
VIRTUAL_NODE_TYPES = frozenset(
    {
        "Note",
        "MarkdownNote",
        "Reroute",
        "PrimitiveNode",
    }
)


@dataclass(frozen=True)
class Node:
    """API形式のノード1つ。"""

    class_type: str
    title: str
    # `inputs`だけは組み立てた後に書き換える。
    # パラメータの適用もseedの差し替えもここへ書く。
    inputs: dict[str, object] = field(default_factory=dict[str, object])


@dataclass(frozen=True)
class Prompt:
    """`POST /prompt`へ渡す内容と、その組み立ての過程で分かったこと。"""

    nodes: dict[str, Node]
    # ノードID -> ウィジェット名 -> `control_after_generate`の値。
    controls: dict[str, dict[str, str]]

    def api(self) -> dict[str, object]:
        """`POST /prompt`の`prompt`に入れる形にする。

        `_meta`はサーバが無視する。
        `--dry-run`で読む時にどのノードか分かるように残す。
        """
        return {
            node_id: {
                "class_type": node.class_type,
                "inputs": node.inputs,
                "_meta": {"title": node.title},
            }
            for node_id, node in self.nodes.items()
        }


def assign_widgets(
    slots: tuple[Slot, ...], values: list[object]
) -> tuple[dict[str, object], dict[str, str]]:
    """`widgets_values`の値へ名前を付ける。

    名前の付いたスロットと名前の無いスロットが交互に来るので、
    素直に前から突き合わせると、
    フロントエンドが足すウィジェットの有無で以降が全てずれる。

    実際に揺れる。
    `LoadVideo`のアップロードボタンの値は、
    `anime-video-upscale`のワークフローにはあり、
    `anime-video-extend`のワークフローには無い。
    どちらもUIで開けば同じように動く。

    そこで名前の付いたスロットを優先する。
    名前の無いスロットが値を食うのは、
    残りの値が残りの名前より多い、つまり余っている時だけにする。

    値が足りない場合と余った場合は例外にする。
    ずれたまま進むと、
    stepsの位置へcfgの値が入るような、
    実行はできるが結果だけが違う壊れ方をする。
    """
    named_left = sum(1 for slot in slots if slot.widget is not None)
    index = 0
    inputs: dict[str, object] = {}
    controls: dict[str, str] = {}
    for slot in slots:
        if slot.widget is not None:
            if len(values) <= index:
                raise ValueError(f"ウィジェットの値が足りません: {values}")
            inputs[slot.widget.name] = values[index]
            index += 1
            named_left -= 1
            continue
        if named_left < len(values) - index:
            if slot.controls is not None:
                controls[slot.controls] = as_text(values[index])
            index += 1
    if index != len(values):
        raise ValueError(f"ウィジェットの値が余りました: {values[index:]}")
    return (inputs, controls)


def _link_table(workflow: dict[str, object]) -> dict[int, tuple[str, int]]:
    """リンクIDから`(出力元ノードID, 出力スロット)`への表。

    UI形式のリンクは`[ID, 出力元, 出力スロット, 入力先, 入力スロット, 型]`である。
    """
    table: dict[int, tuple[str, int]] = {}
    for raw in as_array(workflow.get("links")):
        link = as_array(raw)
        if len(link) < 3:
            continue
        link_id = link[0]
        origin = as_node_id(link[1])
        slot = link[2]
        if isinstance(link_id, bool) or not isinstance(link_id, int):
            continue
        if isinstance(slot, bool) or not isinstance(slot, int) or not origin:
            continue
        table[link_id] = (origin, slot)
    return table


def to_api(workflow: object, node_defs: dict[str, NodeDef]) -> Prompt:
    """UI形式のワークフローをAPI形式へ変換する。"""
    parsed = as_object(workflow)
    links = _link_table(parsed)
    nodes: dict[str, Node] = {}
    controls: dict[str, dict[str, str]] = {}
    for raw in as_array(parsed.get("nodes")):
        node = as_object(raw)
        class_type = as_text(node.get("type"))
        node_id = as_node_id(node.get("id"))
        if not class_type or not node_id:
            raise ValueError(f"ノードの形が読めません: {node}")
        if class_type in VIRTUAL_NODE_TYPES:
            continue
        # 0以外はミュートかバイパスで、
        # バイパスは前後を繋ぎ直す処理が要る。
        # このリポジトリのワークフローは全て0なので、
        # 実装せずに気付ける形で止める。
        if node.get("mode", 0) != 0:
            raise ValueError(f"ノード{node_id}({class_type})が実行対象外の状態です")
        definition = node_defs.get(class_type)
        if definition is None:
            raise ValueError(f"ノード型{class_type}が/object_infoにありません")
        try:
            inputs, node_controls = assign_widgets(
                definition.slots, as_array(node.get("widgets_values"))
            )
        except ValueError as error:
            raise ValueError(f"ノード{node_id}({class_type}): {error}") from error
        for raw_slot in as_array(node.get("inputs")):
            slot = as_object(raw_slot)
            link_id = slot.get("link")
            # 繋がっていない入力は飛ばす。
            # ウィジェットをソケットへ変換しただけのものがこれで、
            # 値は`widgets_values`の側から既に入っている。
            if isinstance(link_id, bool) or not isinstance(link_id, int):
                continue
            if link_id not in links:
                raise ValueError(f"ノード{node_id}のリンク{link_id}が存在しません")
            origin, origin_slot = links[link_id]
            inputs[as_text(slot.get("name"))] = [origin, origin_slot]
        nodes[node_id] = Node(
            class_type=class_type,
            title=as_text(node.get("title")) or class_type,
            inputs=inputs,
        )
        if node_controls:
            controls[node_id] = node_controls
    if not nodes:
        raise ValueError("ワークフローにノードがありません")
    return Prompt(nodes=nodes, controls=controls)


def missing_required(prompt: Prompt, node_defs: dict[str, NodeDef]) -> list[str]:
    """必須入力が埋まっていないノードを挙げる。

    変換がずれた時に、
    ComfyUIへ投げる前に自分で気付くための検査である。

    `values.a`のように名前の前半だけが一致するものも埋まっているとみなす。
    数を増やせる入力は、
    定義では`values`という1つの名前だが、
    ワークフローでは`values.a`や`values.b`として現れる。
    """
    problems: list[str] = []
    for node_id, node in prompt.nodes.items():
        definition = node_defs.get(node.class_type)
        if definition is None:
            continue
        for name in definition.required:
            if name in node.inputs:
                continue
            if any(key.startswith(f"{name}.") for key in node.inputs):
                continue
            problems.append(f"{node_id}({node.class_type})に{name}がありません")
    return problems
