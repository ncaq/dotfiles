"""`main.py`が持つ、外部I/Oを踏まない判断のテスト。

`main.py`の大半はHTTPと`argparse`と待ちの繰り返しだが、
その中に判断が混ざっている。

- `parse_value`: コマンドラインの文字列をウィジェットの型へ直す
- `collect_outputs`: 履歴から保存されたファイルを拾う
- `failure_of`: 履歴が失敗を表しているかどうか
- `positive_int`: `--repeat`が受け付ける範囲

どれもimportして呼ぶだけで確かめられる。
特に`collect_outputs`は、
間違えても例外にならず「表示されるパスが違う」だけの壊れ方をするので、
他のモジュールと同じく実機では気付けない性質を持つ。
"""

import pytest
from main import collect_outputs, failure_of, parse_value, positive_int
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


def test_a_successful_history_is_not_a_failure() -> None:
    assert failure_of({"status": {"status_str": "success"}}) is None


def test_a_history_without_a_status_is_not_a_failure() -> None:
    # 上流が形を変えた時に、成功した生成を失敗として報告するのは避ける。
    # 出力が0件かどうかは呼び出し側が別に見る。
    assert failure_of({}) is None


def test_a_failed_history_is_reported() -> None:
    # ComfyUIは失敗時も履歴を作る。
    # 見ないと`collect_outputs`が空を返し、
    # 何も表示せずに終了コード0で終わるので、
    # 成功したが出力が0件の場合と区別が付かない。
    assert failure_of({"status": {"status_str": "error"}}) is not None


def test_the_failure_carries_the_messages() -> None:
    # どのノードで何が起きたのかは`messages`にしか無い。
    reported = failure_of(
        {
            "status": {
                "status_str": "error",
                "messages": [["execution_error", {"node_type": "KSampler"}]],
            }
        }
    )
    assert reported is not None
    assert "KSampler" in reported


def test_positive_int_accepts_one() -> None:
    assert positive_int("1") == 1


@pytest.mark.parametrize("text", ["0", "-1"])
def test_positive_int_rejects_zero_and_below(text: str) -> None:
    # `range(0)`は空になるので、何も投げずに、何も言わずに正常終了する。
    # 利用者からは成功したのに結果が出ない状態と区別が付かない。
    with pytest.raises(ValueError):
        positive_int(text)


def test_positive_int_rejects_words() -> None:
    with pytest.raises(ValueError):
        positive_int("many")


def test_a_dot_dot_inside_a_name_is_allowed() -> None:
    # 弾くのは経路としての`..`だけである。
    # 名前の一部として現れる`..`まで弾くと、
    # 普通に保存できるファイルが表示できなくなる。
    assert collect_outputs(
        history({"filename": "a..b.png", "subfolder": "", "type": "output"})
    ) == ["a..b.png"]
