"""指示文のリライトの応答解析の単体テスト。

Ollamaの応答は公式が期待する`{"Rewritten": "..."}`のJSONだが、
モデルはコードブロックで包んだり、素の文章で返したりする。
ここで弾いた応答は呼び出し側が翻訳や原文へ倒すので、
どの形を受け付けてどの形を拒否するのかが生成結果に直接効く。
"""

import pytest
import rewrite


def test_reads_plain_json() -> None:
    """素のJSONをそのまま読む。"""
    assert rewrite.rewritten_text('{"Rewritten": "Make the keyboard red."}') == (
        "Make the keyboard red."
    )


def test_strips_code_fence() -> None:
    """コードブロックで包まれていても剥がして読む。"""
    response = '```json\n{"Rewritten": "Make the keyboard red."}\n```'
    assert rewrite.rewritten_text(response) == "Make the keyboard red."


def test_strips_code_fence_without_closing() -> None:
    """閉じフェンスが無くても読む。生成が上限で切れると起きる。"""
    response = '```json\n{"Rewritten": "Make the keyboard red."}'
    assert rewrite.rewritten_text(response) == "Make the keyboard red."


def test_ignores_text_after_code_fence() -> None:
    """閉じフェンスより後ろの説明文は落とす。

    JSONだけを返せと書いてあっても、
    モデルは書き換えの意図を後ろに足してくることがある。
    ここで弾くと使える書き換えを捨てて翻訳へ退避することになる。
    """
    response = (
        '```json\n{"Rewritten": "Make the keyboard red."}\n```\n'
        "This keeps the rest of the desk unchanged."
    )
    assert rewrite.rewritten_text(response) == "Make the keyboard red."


def test_rejects_empty_code_fence() -> None:
    """中身の無いコードブロックは拒否する。"""
    with pytest.raises(ValueError, match="non-JSON rewrite"):
        rewrite.rewritten_text("```\n```")


def test_collapses_whitespace() -> None:
    """改行や連続する空白を1つに潰す。指示文は1行で渡すため。"""
    response = '{"Rewritten": "Make the\\nkeyboard   red."}'
    assert rewrite.rewritten_text(response) == "Make the keyboard red."


broken_responses: list[tuple[str, str]] = [
    ("Make the keyboard red.", "non-JSON rewrite"),
    ('["Make the keyboard red."]', "not an object"),
    ('{"rewritten": "Make the keyboard red."}', "no Rewritten string"),
    ('{"Rewritten": 42}', "no Rewritten string"),
    ('{"Rewritten": "   "}', "empty rewrite"),
]


@pytest.mark.parametrize(("response", "message"), broken_responses)
def test_rejects_broken_response(response: str, message: str) -> None:
    """期待した形でない応答は、どこがおかしいのか分かる形で拒否する。"""
    with pytest.raises(ValueError, match=message):
        rewrite.rewritten_text(response)


def test_messages_split_system_and_user() -> None:
    """規則はsystemへ、指示文はuserへ分けて載せる。"""
    messages = rewrite.build_messages("赤くして", None)

    assert [message["role"] for message in messages] == ["system", "user"]
    assert messages[1]["content"] == "User Input: 赤くして\n\nRewritten Prompt:"
    # 画像が無ければ`images`は付けない。
    # 空のリストを送るとOllamaがマルチモーダルの経路へ入る。
    assert "images" not in messages[1]


def test_messages_carry_image() -> None:
    """画像はuserのメッセージに付ける。"""
    messages = rewrite.build_messages("赤くして", "BASE64")

    assert messages[1]["images"] == ["BASE64"]
    assert "images" not in messages[0]


def test_system_message_keeps_official_rules() -> None:
    """systemへ載せる規則が公式のまま欠けていない。"""
    system = rewrite.build_messages("赤くして", None)[0]["content"]

    assert isinstance(system, str)
    assert system.startswith("# Edit Prompt Enhancer")
    # タスク種別ごとの規則が丸ごと入っていることを確認する。
    # ここが欠けると書き換えの質が静かに落ちる。
    for section in [
        "Add, Delete, Replace Tasks",
        "Text Editing Tasks",
        "Human (ID) Editing Tasks",
        "Style Conversion or Enhancement Tasks",
        "Content Filling Tasks",
        "Multi-Image Tasks",
    ]:
        assert section in system
