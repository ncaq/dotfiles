"""`params.py`のフラグ名の決め方と、値の書き込みのテスト。

名前の決め方は実機で確かめにくい。
`--help`を見れば分かるが、
どういう時にウィジェット名から離れるのかは、
ワークフローを1つ見ても読み取れない。
"""

import pytest
from convert import Node, Prompt
from nodedef import NodeDef, Slot, Widget
from params import apply, apply_seed, parameters, resolve_names, slug


def test_slug_keeps_ascii_words_only() -> None:
    assert slug("Positive Prompt") == "positive-prompt"
    assert slug("unet_name") == "unet-name"


def test_slug_gives_up_on_non_ascii() -> None:
    # 日本語のタイトルからはフラグ名を作れない。
    assert slug("生成寸法") == ""


def test_slug_gives_up_when_it_does_not_start_with_a_letter() -> None:
    # `参考画像2`のようなタイトルからは数字しか残らない。
    # `--2`はargparseが負の数と区別できずに壊れる。
    assert slug("参考画像2") == ""


def test_unique_names_stay_as_they_are() -> None:
    assert resolve_names([["seed"], ["steps"]]) == ["seed", "steps"]


def test_collision_falls_through_to_the_next_candidate() -> None:
    # 衝突した組だけが次の候補へ降りる。巻き込まれない方はそのまま。
    assert resolve_names([["text", "positive"], ["text", "negative"], ["cfg"]]) == [
        "positive",
        "negative",
        "cfg",
    ]


def test_reserved_names_are_not_used() -> None:
    # `--seed`のような全体のオプションが先に取っている名前には譲る。
    assert resolve_names([["seed", "sampler-seed"]], frozenset({"seed"})) == [
        "sampler-seed"
    ]


def test_undecidable_names_do_not_collide() -> None:
    # 候補を使い切っても、名前が重複したまま返してはいけない。
    # argparseが同じフラグを2度受け取って落ちる。
    assert len(set(resolve_names([["a"], ["a"]]))) == 2


TEXT = NodeDef(
    slots=(
        Slot(widget=Widget(name="text", kind="STRING", choices=None), controls=None),
    ),
    required=("text",),
)
SAMPLER = NodeDef(
    slots=(
        Slot(widget=Widget(name="seed", kind="INT", choices=None), controls=None),
        Slot(widget=None, controls="seed"),
    ),
    required=("seed",),
)


def workflow(*inputs: object) -> object:
    return {"extra": {"linearData": {"inputs": list(inputs)}}}


def prompt_of(*nodes: tuple[str, str, str]) -> Prompt:
    return Prompt(
        nodes={
            node_id: Node(class_type=class_type, title=title, inputs={"text": "既定"})
            for node_id, class_type, title in nodes
        },
        controls={},
    )


def test_widget_name_becomes_the_flag() -> None:
    params = parameters(
        workflow([4, "text"]),
        prompt_of(("4", "CLIPTextEncode", "")),
        {"CLIPTextEncode": TEXT},
    )
    assert [parameter.name for parameter in params] == ["text"]


def test_colliding_widgets_use_the_node_title() -> None:
    # `anima-standard`のポジティブとネガティブがこの形になる。
    params = parameters(
        workflow([4, "text"], [5, "text"]),
        prompt_of(
            ("4", "CLIPTextEncode", "Positive Prompt"),
            ("5", "CLIPTextEncode", "Negative Prompt"),
        ),
        {"CLIPTextEncode": TEXT},
    )
    assert [parameter.name for parameter in params] == [
        "positive-prompt",
        "negative-prompt",
    ]


def test_colliding_widgets_without_usable_titles_use_the_node_id() -> None:
    params = parameters(
        workflow([4, "text"], [5, "text"]),
        prompt_of(("4", "CLIPTextEncode", "生成内容"), ("5", "CLIPTextEncode", "除外")),
        {"CLIPTextEncode": TEXT},
    )
    assert [parameter.name for parameter in params] == ["node4-text", "node5-text"]


def test_seed_is_not_a_parameter() -> None:
    # 全体の`--seed`が全てのサンプラーへ配るので、1つのノードを指すフラグは持たない。
    params = parameters(
        workflow([7, "seed"]), prompt_of(("7", "KSampler", "")), {"KSampler": SAMPLER}
    )
    assert params == []


def test_description_and_default_come_from_the_workflow() -> None:
    params = parameters(
        workflow([4, "text", {"description": "生成する画像の内容"}]),
        prompt_of(("4", "CLIPTextEncode", "")),
        {"CLIPTextEncode": TEXT},
    )
    assert params[0].description == "生成する画像の内容"
    assert params[0].default == "既定"


def test_input_pointing_at_a_missing_node_is_an_error() -> None:
    with pytest.raises(ValueError):
        parameters(
            workflow([9, "text"]),
            prompt_of(("4", "CLIPTextEncode", "")),
            {"CLIPTextEncode": TEXT},
        )


def test_input_pointing_at_a_missing_widget_is_an_error() -> None:
    with pytest.raises(ValueError):
        parameters(
            workflow([4, "nonexistent"]),
            prompt_of(("4", "CLIPTextEncode", "")),
            {"CLIPTextEncode": TEXT},
        )


def test_apply_writes_into_the_prompt() -> None:
    prompt = prompt_of(("4", "CLIPTextEncode", ""))
    params = parameters(workflow([4, "text"]), prompt, {"CLIPTextEncode": TEXT})
    apply(prompt, params[0], "1girl")
    assert prompt.nodes["4"].inputs["text"] == "1girl"


def test_apply_seed_reaches_every_randomizing_widget() -> None:
    # `anima-standard`はサンプラーが3つあり、揃って動く必要がある。
    prompt = Prompt(
        nodes={
            node_id: Node(class_type="KSampler", title="", inputs={"seed": 0})
            for node_id in ("7", "14", "17")
        },
        controls={node_id: {"seed": "randomize"} for node_id in ("7", "14", "17")},
    )
    assert len(apply_seed(prompt, 314)) == 3
    assert all(node.inputs["seed"] == 314 for node in prompt.nodes.values())


def test_apply_seed_leaves_fixed_widgets_alone() -> None:
    # UIで意図して固定したものが、APIから投げた時だけ動くのはおかしい。
    prompt = Prompt(
        nodes={"5": Node(class_type="KSampler", title="", inputs={"seed": 42})},
        controls={"5": {"seed": "fixed"}},
    )
    assert apply_seed(prompt, 314) == []
    assert prompt.nodes["5"].inputs["seed"] == 42
