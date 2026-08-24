"""`nodedef.py`の、ノード定義からウィジェットの並びを組み立てる部分のテスト。

ここがずれると、
`widgets_values`の値へ1つずれた名前が付く。
実行はできてしまい、
stepsの位置にcfgの値が入った画像が出るだけなので、
実機で1回動かしても気付けない。
"""

import pytest
from nodedef import Widget, parse


def spec(kind: object, **options: object) -> list[object]:
    """入力定義1つ分の`[型, オプション]`を組み立てる。

    `["INT", {}]`と直接書くと空の辞書の要素の型が決まらず、
    pyrightのstrictが部分的に不明な引数として止める。
    """
    return [kind, options]


def definition(
    *inputs: tuple[str, object], optional: tuple[tuple[str, object], ...] = ()
) -> dict[str, object]:
    """`/object_info`のノード定義1つ分を、入力の並びから組み立てる。"""
    return {
        "input": {"required": dict(inputs), "optional": dict(optional)},
        "input_order": {
            "required": [name for name, _ in inputs],
            "optional": [name for name, _ in optional],
        },
    }


def slots(
    *inputs: tuple[str, object], optional: tuple[tuple[str, object], ...] = ()
) -> list[str | None]:
    """組み立てたスロットの名前だけを並べる。Noneはフロントエンドだけのもの。"""
    node_def = parse({"Example": definition(*inputs, optional=optional)})["Example"]
    return [
        slot.widget.name if slot.widget is not None else None for slot in node_def.slots
    ]


def test_sockets_do_not_take_a_slot() -> None:
    # MODELのようにソケットでしか繋げない入力は`widgets_values`に現れない。
    assert slots(("model", spec("MODEL")), ("steps", spec("INT"))) == ["steps"]


def test_force_input_does_not_take_a_slot() -> None:
    # ウィジェットで描ける型でも`forceInput`ならソケットとして描かれる。
    # 落とさないと以降の名前が全て1つずれる。
    assert slots(("steps", spec("INT", forceInput=True)), ("cfg", spec("FLOAT"))) == [
        "cfg"
    ]


def test_optional_widgets_come_after_the_required_ones() -> None:
    # `optional`のウィジェットも`widgets_values`の位置を占める。
    # `FaceDetailer`の`inpaint_model`から後ろがこれに当たる。
    # required→optionalという並びの仮定はここでしか表現されていないので、
    # ずれると全ての名前が1つずれる。
    assert slots(
        ("steps", spec("INT")),
        optional=(("cycle", spec("INT")), ("tiled_encode", spec("BOOLEAN"))),
    ) == ["steps", "cycle", "tiled_encode"]


def test_optional_sockets_do_not_take_a_slot() -> None:
    # `optional`の側にもソケットでしか繋げない入力が混ざる。
    # `FaceDetailer`の`sam_model_opt`がこれで、飛ばさないと以降がずれる。
    assert slots(
        ("steps", spec("INT")),
        optional=(("sam_model_opt", spec("SAM_MODEL")), ("cycle", spec("INT"))),
    ) == ["steps", "cycle"]


def test_seed_gets_an_implicit_control_slot() -> None:
    # フロントエンドの`useIntWidget.ts`は、
    # 入力定義が何も書いていなくても名前がseedなら制御ウィジェットを足す。
    assert slots(("seed", spec("INT")), ("steps", spec("INT"))) == [
        "seed",
        None,
        "steps",
    ]


def test_noise_seed_gets_an_implicit_control_slot() -> None:
    assert slots(("noise_seed", spec("INT"))) == ["noise_seed", None]


def test_declared_control_after_generate_adds_a_slot() -> None:
    # 名前がseedでなくても、定義が要求すれば付く。
    assert slots(("count", spec("INT", control_after_generate=True))) == [
        "count",
        None,
    ]


def test_declared_false_control_after_generate_does_not_add_a_slot() -> None:
    # 明示的に偽と書かれていれば、名前がseedでも付かない。
    # `dict.get`の既定値は鍵が無い時にしか効かないので、ここで固定する。
    assert slots(("seed", spec("INT", control_after_generate=False))) == ["seed"]


@pytest.mark.parametrize("option", ["image_upload", "video_upload", "audio_upload"])
def test_upload_button_takes_a_slot(option: str) -> None:
    # アップロードボタンもノード定義には無いのに位置だけを占める。
    upload: dict[str, object] = {option: True, "options": []}
    assert slots(("file", spec("COMBO", **upload))) == ["file", None]


def test_combo_choices_from_the_legacy_shape() -> None:
    # 型の位置に選択肢の配列を直接書く古い形。
    node_def = parse({"Example": definition(("sampler", [["euler", "ddim"]]))})[
        "Example"
    ]
    assert node_def.widget("sampler") == Widget(
        name="sampler", kind="COMBO", choices=("euler", "ddim")
    )


def test_combo_choices_from_the_options_shape() -> None:
    # 型が`"COMBO"`でオプションの`options`に選択肢が入る新しい形。
    node_def = parse(
        {"Example": definition(("sampler", spec("COMBO", options=["euler", "ddim"])))}
    )["Example"]
    assert node_def.widget("sampler") == Widget(
        name="sampler", kind="COMBO", choices=("euler", "ddim")
    )


def test_input_order_wins_over_the_input_mapping() -> None:
    # 並びの正本は`input_order`である。
    node_def = parse(
        {
            "Example": {
                "input": {"required": {"b": spec("INT"), "a": spec("INT")}},
                "input_order": {"required": ["a", "b"]},
            }
        }
    )["Example"]
    assert [slot.widget.name for slot in node_def.slots if slot.widget] == ["a", "b"]


def test_frontend_widget_slots_override_the_definition() -> None:
    # LoRA Managerのノードは、
    # 定義に無いウィジェットを拡張が前後に足すので書き写してある。
    node_def = parse(
        {
            "Lora Loader (LoraManager)": {
                "input": {"required": {"text": spec("AUTOCOMPLETE_TEXT_LORAS")}},
                "input_order": {"required": ["model", "text"]},
            }
        }
    )["Lora Loader (LoraManager)"]
    assert [slot.widget.name if slot.widget else None for slot in node_def.slots] == [
        None,
        "text",
        None,
    ]
    # 定義がソケット用の型を書いていても、書き写した側は文字列として扱う。
    assert node_def.widget("text") == Widget(name="text", kind="STRING", choices=None)


def test_frontend_widget_slots_prefer_the_required_definition() -> None:
    # 同じ名前が`required`と`optional`の両方にある時の解釈を固定する。
    # `_declared_slots`は両方を別のスロットとして扱うので、
    # 書き写した側だけが後から見た方で上書きすると、
    # 同じモジュールの中で解釈が食い違う。
    node_def = parse(
        {
            "Lora Loader (LoraManager)": {
                "input": {
                    "required": {"text": spec("STRING")},
                    "optional": {"text": spec("COMBO", options=["a", "b"])},
                },
                "input_order": {"required": ["text"], "optional": ["text"]},
            }
        }
    )["Lora Loader (LoraManager)"]
    assert node_def.widget("text") == Widget(
        name="text", kind="STRING", choices=None, dynamic=False
    )


def test_required_names_are_kept() -> None:
    node_def = parse(
        {"Example": definition(("model", spec("MODEL")), ("steps", spec("INT")))}
    )["Example"]
    assert node_def.required == ("model", "steps")


def test_non_object_response_is_rejected() -> None:
    with pytest.raises(ValueError):
        parse([])
