"""`main.py`が持つ、外部I/Oを踏まない判断のテスト。

`main.py`の大半はHTTPと`argparse`と待ちの繰り返しだが、
その中に判断が混ざっている。

- `parse_value`: コマンドラインの文字列をウィジェットの型へ直す
- `collect_outputs`: 履歴から保存されたファイルを拾う

どちらもimportして呼ぶだけで確かめられる。
特に`collect_outputs`は、
間違えても例外にならず「表示されるパスが違う」だけの壊れ方をするので、
他のモジュールと同じく実機では気付けない性質を持つ。
"""

import pytest
from main import collect_outputs, parse_value
from nodedef import Widget


def widget(kind: str, choices: tuple[str, ...] | None = None) -> Widget:
    return Widget(name="w", kind=kind, choices=choices, dynamic=False)


def test_int_is_parsed() -> None:
    assert parse_value(widget("INT"), "20") == 20


def test_float_is_parsed() -> None:
    assert parse_value(widget("FLOAT"), "5.5") == 5.5


@pytest.mark.parametrize("text", ["true", "TRUE", "1", "yes", "on"])
def test_truthy_words_are_accepted(text: str) -> None:
    assert parse_value(widget("BOOLEAN"), text) is True


@pytest.mark.parametrize("text", ["false", "FALSE", "0", "no", "off"])
def test_falsy_words_are_accepted(text: str) -> None:
    assert parse_value(widget("BOOLEAN"), text) is False


def test_other_words_are_not_booleans() -> None:
    # 読めない値を真偽値のどちらかへ倒すと、
    # 打ち間違いが黙って逆の設定になる。
    with pytest.raises(ValueError):
        parse_value(widget("BOOLEAN"), "maybe")


def test_combo_accepts_a_listed_choice() -> None:
    assert parse_value(widget("COMBO", ("euler", "ddim")), "ddim") == "ddim"


def test_combo_rejects_an_unlisted_choice() -> None:
    with pytest.raises(ValueError):
        parse_value(widget("COMBO", ("euler", "ddim")), "nonexistent")


def test_combo_without_choices_passes_through() -> None:
    # 選択肢を読めなかったCOMBOで全ての値を弾くと、何も指定できなくなる。
    assert parse_value(widget("COMBO"), "anything") == "anything"


def test_string_passes_through() -> None:
    assert parse_value(widget("STRING"), "1girl, {a|b}") == "1girl, {a|b}"


def history(*items: dict[str, object]) -> dict[str, object]:
    return {"outputs": {"18": {"images": list(items)}}}


def test_saved_files_are_collected() -> None:
    assert collect_outputs(
        history({"filename": "a.png", "subfolder": "anima", "type": "output"})
    ) == ["anima/a.png"]


def test_files_without_a_subfolder_are_not_prefixed() -> None:
    assert collect_outputs(
        history({"filename": "a.png", "subfolder": "", "type": "output"})
    ) == ["a.png"]


def test_temporary_files_are_skipped() -> None:
    # 入力として置き直しただけのものは`type`が`output`にならない。
    # 拾うと、利用者へ存在しない出力を見せることになる。
    assert (
        collect_outputs(
            history({"filename": "a.png", "subfolder": "", "type": "temp"})
        )
        == []
    )


def test_every_output_key_is_read() -> None:
    # 保存ノードの種類ごとに`images`や`gifs`とキーが変わる。
    # 決め打ちにすると動画のワークフローで何も表示されなくなる。
    assert collect_outputs(
        {
            "outputs": {
                "18": {"images": [{"filename": "a.png", "type": "output"}]},
                "19": {"gifs": [{"filename": "b.webm", "type": "output"}]},
            }
        }
    ) == ["a.png", "b.webm"]


def test_a_broken_history_yields_nothing() -> None:
    assert collect_outputs([]) == []


def test_an_absolute_filename_is_an_error() -> None:
    # `Path(output_dir) / "/etc/passwd"`は左辺を捨てる。
    # 出力先の外を指すパスが、
    # そこに保存されたかのように表示される。
    with pytest.raises(ValueError):
        collect_outputs(
            history({"filename": "/etc/passwd", "subfolder": "", "type": "output"})
        )


@pytest.mark.parametrize(
    "item",
    [
        {"filename": "../a.png", "subfolder": "", "type": "output"},
        {"filename": "a.png", "subfolder": "..", "type": "output"},
        {"filename": "a.png", "subfolder": "anima/../../etc", "type": "output"},
        {"filename": "a.png", "subfolder": "/etc", "type": "output"},
    ],
)
def test_escaping_the_output_directory_is_an_error(item: dict[str, object]) -> None:
    # 今は表示するだけなので実害は限られるが、
    # 後からこの結果を開く処理を足した時にパストラバーサルへ育つ。
    with pytest.raises(ValueError):
        collect_outputs(history(item))


def test_a_dot_dot_inside_a_name_is_allowed() -> None:
    # 弾くのは経路としての`..`だけである。
    # 名前の一部として現れる`..`まで弾くと、
    # 普通に保存できるファイルが表示できなくなる。
    assert collect_outputs(
        history({"filename": "a..b.png", "subfolder": "", "type": "output"})
    ) == ["a..b.png"]
