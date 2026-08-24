"""`convert.py`のUI形式からAPI形式への変換のテスト。

位置合わせと、リンクの解決と、落とすものの3つを見る。
"""

import pytest
from convert import Node, Prompt, assign_widgets, missing_required, to_api
from nodedef import NodeDef, Slot, Widget


def widget(name: str, kind: str = "INT") -> Slot:
    return Slot(widget=Widget(name=name, kind=kind, choices=None), controls=None)


def control(name: str) -> Slot:
    return Slot(widget=None, controls=name)


UPLOAD = Slot(widget=None, controls=None)

SAMPLER = NodeDef(
    slots=(widget("seed"), control("seed"), widget("steps")),
    required=("model", "seed", "steps"),
)
SAVER = NodeDef(slots=(widget("filename_prefix", "STRING"),), required=("images",))


def test_named_slots_take_values_in_order() -> None:
    inputs, controls = assign_widgets((widget("a"), widget("b")), [1, 2])
    assert inputs == {"a": 1, "b": 2}
    assert controls == {}


def test_control_slot_is_kept_out_of_the_inputs() -> None:
    # `control_after_generate`はAPIへ送らない。
    # 送る値ではなく、振り直す約束があったことの記録として返す。
    inputs, controls = assign_widgets(SAMPLER.slots, [7, "randomize", 20])
    assert inputs == {"seed": 7, "steps": 20}
    assert controls == {"seed": "randomize"}


def test_missing_frontend_slot_is_skipped() -> None:
    # `LoadVideo`のアップロードボタンの値は、書かれていないワークフローがある。
    # 素直に前から突き合わせると、以降の名前が全て1つずれる。
    inputs, controls = assign_widgets((widget("file", "COMBO"), UPLOAD), ["a.mp4"])
    assert inputs == {"file": "a.mp4"}
    assert controls == {}


def test_present_frontend_slot_is_consumed() -> None:
    inputs, _ = assign_widgets((widget("file", "COMBO"), UPLOAD), ["a.mp4", "image"])
    assert inputs == {"file": "a.mp4"}


def test_too_few_values_is_an_error() -> None:
    # 足りないまま進むと、後ろのウィジェットが既定値のまま実行される。
    with pytest.raises(ValueError):
        assign_widgets((widget("a"), widget("b")), [1])


def test_too_many_values_is_an_error() -> None:
    # 余ったまま進むのは、こちらが並びを取り違えている合図である。
    with pytest.raises(ValueError):
        assign_widgets((widget("a"),), [1, 2])


def graph(*nodes: dict[str, object], links: list[object] | None = None) -> object:
    return {"nodes": list(nodes), "links": links or []}


def test_links_become_node_references() -> None:
    prompt = to_api(
        graph(
            {
                "id": 1,
                "type": "Sampler",
                "widgets_values": [7, "fixed", 20],
                "outputs": [{"name": "LATENT", "links": [5]}],
            },
            {
                "id": 2,
                "type": "Saver",
                "widgets_values": ["out"],
                "inputs": [{"name": "images", "link": 5}],
            },
            links=[[5, 1, 0, 2, 0, "LATENT"]],
        ),
        {"Sampler": SAMPLER, "Saver": SAVER},
    )
    assert prompt.nodes["2"].inputs == {"filename_prefix": "out", "images": ["1", 0]}


def test_unconnected_input_keeps_the_widget_value() -> None:
    # ウィジェットをソケットへ変換しただけの入力は繋がっていない。
    # 値は`widgets_values`の側から既に入っているので、上書きしてはいけない。
    prompt = to_api(
        graph(
            {
                "id": 1,
                "type": "Saver",
                "widgets_values": ["out"],
                "inputs": [{"name": "filename_prefix", "link": None}],
            }
        ),
        {"Saver": SAVER},
    )
    assert prompt.nodes["1"].inputs == {"filename_prefix": "out"}


def test_virtual_nodes_are_dropped() -> None:
    # `Note`はサーバ側に実装が無い。残すと実行前の検証で落ちる。
    prompt = to_api(
        graph(
            {"id": 1, "type": "Saver", "widgets_values": ["out"]},
            {"id": 2, "type": "Note", "widgets_values": ["覚え書き"]},
        ),
        {"Saver": SAVER},
    )
    assert list(prompt.nodes) == ["1"]


def test_muted_node_is_an_error() -> None:
    # ミュートとバイパスは前後を繋ぎ直す処理が要る。
    # 実装していないので、黙って通さずに気付ける形で止める。
    with pytest.raises(ValueError):
        to_api(
            graph({"id": 1, "type": "Saver", "widgets_values": ["out"], "mode": 4}),
            {"Saver": SAVER},
        )


def test_unknown_node_type_is_an_error() -> None:
    with pytest.raises(ValueError):
        to_api(graph({"id": 1, "type": "Nonexistent"}), {})


def test_dangling_link_is_an_error() -> None:
    with pytest.raises(ValueError):
        to_api(
            graph(
                {
                    "id": 1,
                    "type": "Saver",
                    "widgets_values": ["out"],
                    "inputs": [{"name": "images", "link": 9}],
                }
            ),
            {"Saver": SAVER},
        )


def test_empty_graph_is_an_error() -> None:
    # 全部が仮想ノードだった場合もここへ来る。
    with pytest.raises(ValueError):
        to_api(graph(), {})


def test_controls_are_reported_per_node() -> None:
    prompt = to_api(
        graph({"id": 3, "type": "Sampler", "widgets_values": [0, "randomize", 20]}),
        {"Sampler": SAMPLER},
    )
    assert prompt.controls == {"3": {"seed": "randomize"}}


def test_missing_required_reports_the_gap() -> None:
    prompt = Prompt(
        nodes={"1": Node(class_type="Sampler", title="Sampler", inputs={"seed": 0})},
        controls={},
    )
    problems = missing_required(prompt, {"Sampler": SAMPLER})
    assert len(problems) == 2
    assert all("1(Sampler)" in problem for problem in problems)


def test_autogrow_inputs_count_as_present() -> None:
    # 数を増やせる入力は、定義では`values`だがワークフローでは`values.a`になる。
    node_def = NodeDef(slots=(), required=("values",))
    prompt = Prompt(
        nodes={
            "1": Node(class_type="Math", title="Math", inputs={"values.a": ["2", 0]})
        },
        controls={},
    )
    assert missing_required(prompt, {"Math": node_def}) == []
