"""指示文のリライトの入力の組み立てと応答解析と、出力の寸法の決め方の単体テスト。

PE-I2Iは思考の後に`{"rewritten_prompt": "...", "wh_ratio": "", "ratio_follow": "<image1>"}`のJSONを出すが、
思考が上限で切れたり、思考の中に波括弧が出てきたりする。
ここで弾いた応答は呼び出し側が翻訳や原文へ倒すので、
どの形を受け付けてどの形を拒否するのかが生成結果に直接効く。
"""

import pytest
import rewrite


def prompt_of(generated: str) -> str:
    return rewrite.parse_rewrite(generated).prompt


def test_reads_answer_after_thinking() -> None:
    """思考を閉じた後のJSONを全ての欄ごと読む。"""
    generated = (
        "The image shows a keyboard.\n</think>\n\n"
        '{"rewritten_prompt": "Make the keyboard red.", "wh_ratio": "", "ratio_follow": "<image1>"}'
    )
    assert rewrite.parse_rewrite(generated) == rewrite.Rewrite(
        prompt="Make the keyboard red.", wh_ratio="", ratio_follow="<image1>"
    )


def test_ignores_json_in_thinking() -> None:
    """思考の中に出てきたJSONは使わない。

    思考の途中で下書きのJSONを書くことがあり、
    それを拾うと最終的な回答ではない指示文で生成することになる。
    """
    generated = (
        'Draft: {"rewritten_prompt": "Draft."}\n</think>\n'
        '{"rewritten_prompt": "Final."}'
    )
    assert prompt_of(generated) == "Final."


def test_reads_last_object_in_answer() -> None:
    """回答に複数のオブジェクトがあれば末尾のものを使う。公式の回答は末尾に出る。"""
    generated = (
        '</think>\n{"note": "ignored"}\nSome text.\n{"rewritten_prompt": "Final."}'
    )
    assert prompt_of(generated) == "Final."


def test_skips_trailing_object_without_prompt() -> None:
    """末尾のオブジェクトに指示文が無ければ、その前の候補へ戻る。"""
    generated = '</think>\n{"rewritten_prompt": "Final."}\n{"note": "trailing"}'
    assert prompt_of(generated) == "Final."


def test_ignores_braces_after_answer() -> None:
    """回答の後ろに波括弧を含む文章が続いても読める。

    最初の`{`から最後の`}`までを取る作りだと、ここで範囲が伸びて読めなくなる。
    """
    generated = '</think>\n{"rewritten_prompt": "Final."}\nSee {details}.'
    assert prompt_of(generated) == "Final."


def test_keeps_braces_inside_string() -> None:
    """指示文の中の波括弧で対応が崩れない。"""
    generated = '</think>\n{"rewritten_prompt": "Write \\"{x}\\" on the sign."}'
    assert prompt_of(generated) == 'Write "{x}" on the sign.'


def test_accepts_misspelled_key() -> None:
    """公式の実装と同じく綴り違いの`rewrited_prompt`も受け付ける。"""
    assert prompt_of('</think>{"rewrited_prompt": "Final."}') == "Final."


def test_reads_without_think_tags() -> None:
    """思考のタグがデコードで落とされていても末尾のJSONを読む。"""
    generated = 'The image shows a keyboard.\n{"rewritten_prompt": "Final."}'
    assert prompt_of(generated) == "Final."


def test_collapses_whitespace() -> None:
    """改行や連続する空白を1つに潰す。指示文は1行で渡すため。"""
    generated = '</think>{"rewritten_prompt": "Make the\\nkeyboard   red."}'
    assert prompt_of(generated) == "Make the keyboard red."


def test_tolerates_missing_ratio_fields() -> None:
    """比率の欄が無いか文字列でなくても、指示文が読めれば受け付けて空として扱う。"""
    generated = '</think>{"rewritten_prompt": "Final.", "wh_ratio": 16}'
    assert rewrite.parse_rewrite(generated) == rewrite.Rewrite(
        prompt="Final.", wh_ratio="", ratio_follow=""
    )


def test_rejects_unfinished_thinking() -> None:
    """思考が閉じないまま終わった生成は拒否する。生成が上限で切れると起きる。"""
    generated = '<think>\nDraft: {"rewritten_prompt": "Draft."}'
    with pytest.raises(ValueError, match="before finishing"):
        rewrite.parse_rewrite(generated)


broken_responses: list[str] = [
    "</think>\nMake the keyboard red.",
    '</think>\n["Make the keyboard red."]',
    '</think>\n{"Rewritten": "Make the keyboard red."}',
    '</think>\n{"rewritten_prompt": 42}',
    '</think>\n{"rewritten_prompt": "   "}',
    '</think>\n{"rewritten_prompt": "Make the keyboard red."',
]


@pytest.mark.parametrize("generated", broken_responses)
def test_rejects_broken_response(generated: str) -> None:
    """期待した形でない応答は拒否する。"""
    with pytest.raises(ValueError, match="no rewritten_prompt"):
        rewrite.parse_rewrite(generated)


def test_prompt_places_images_before_instruction() -> None:
    """画像は枚数分だけ指示文の前に並べ、思考ありの前置きで終える。"""
    prompt = rewrite.build_prompt("RULES", "赤くして", 2)

    assert prompt == (
        "<|im_start|>system\nRULES<|im_end|>\n"
        "<|im_start|>user\n"
        "<|vision_start|><|image_pad|><|vision_end|>"
        "<|vision_start|><|image_pad|><|vision_end|>"
        "赤くして<|im_end|>\n"
        "<|im_start|>assistant\n<think>\n"
    )


def test_prompt_starts_with_chat_marker() -> None:
    """ComfyUIのトークナイザが組み込みのテンプレートを被せないよう`<|im_start|>`で始める。"""
    assert rewrite.build_prompt("RULES", "赤くして", 0).startswith("<|im_start|>")


def answer(wh_ratio: str = "", ratio_follow: str = "") -> rewrite.Rewrite:
    return rewrite.Rewrite(prompt="Edit.", wh_ratio=wh_ratio, ratio_follow=ratio_follow)


landscape = (1200, 800)
portrait = (800, 1200)


def test_canvas_follows_first_image_like_encoder() -> None:
    """1枚目に従う時は`TextEncodeQwenImage21`が作るlatentと同じ寸法になる。

    `sqrt(2048 * 2048 * 1.5) / 32 = 78.38`と`sqrt(2048 * 2048 / 1.5) / 32 = 52.26`を丸める。
    """
    size = rewrite.canvas_size(answer(ratio_follow="<image1>"), [landscape], 2048)
    assert size == (78 * 32, 52 * 32)


def test_canvas_follows_other_image() -> None:
    """`ratio_follow`が2枚目を指せば2枚目の比率を引き継ぐ。"""
    size = rewrite.canvas_size(
        answer(ratio_follow="<image2>"), [landscape, portrait], 2048
    )
    assert size == (52 * 32, 78 * 32)


def test_canvas_uses_official_preset() -> None:
    """公式の表にある比率はその寸法をそのまま使う。"""
    size = rewrite.canvas_size(answer(wh_ratio="16:9"), [portrait], 2048)
    assert size == (2752, 1536)


def test_canvas_scales_official_preset() -> None:
    """解像度が2048でなければ表の寸法を縮尺して32の倍数へ丸める。"""
    size = rewrite.canvas_size(answer(wh_ratio="16:9"), [portrait], 1024)
    assert size == (1376, 768)


def test_canvas_reads_unlisted_ratio() -> None:
    """表に無い比率でも読めれば同じ総画素へ揃える。"""
    size = rewrite.canvas_size(answer(wh_ratio="2:1"), [portrait], 2048)
    assert size == (2912, 1440)


unreadable_answers: list[rewrite.Rewrite] = [
    answer(),
    answer(ratio_follow="<image3>"),
    answer(ratio_follow="<image0>"),
    answer(ratio_follow="image2"),
    answer(wh_ratio="wide"),
    answer(wh_ratio="0:1"),
]


@pytest.mark.parametrize("unreadable", unreadable_answers)
def test_canvas_falls_back_to_first_image(unreadable: rewrite.Rewrite) -> None:
    """比率の欄が読めないか渡していない画像を指す時は1枚目に従う。"""
    size = rewrite.canvas_size(unreadable, [landscape, portrait], 2048)
    assert size == rewrite.canvas_size(None, [landscape], 2048)


def test_canvas_without_rewrite_follows_first_image() -> None:
    """書き換えに失敗した時は1枚目に従う。"""
    assert rewrite.canvas_size(None, [portrait, landscape], 2048) == (52 * 32, 78 * 32)


def test_canvas_without_images_is_square() -> None:
    """画像も比率も無ければ正方形にする。"""
    assert rewrite.canvas_size(None, [], 2048) == (2048, 2048)
