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


def test_prompt_keeps_official_layout() -> None:
    """公式と同じ組み立てでシステムプロンプトと指示文を並べる。"""
    prompt = rewrite.build_prompt("赤くして")

    assert prompt.startswith("# Edit Prompt Enhancer")
    assert prompt.endswith("\n\nUser Input: 赤くして\n\nRewritten Prompt:")
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
        assert section in prompt
