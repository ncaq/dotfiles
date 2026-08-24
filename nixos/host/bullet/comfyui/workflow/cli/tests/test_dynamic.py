"""`dynamic.py`の`{a|b|c}`の展開のテスト。

構文の規則はフロントエンドの`formatUtil.ts`にあり、
入れ子とエスケープの扱いに細かい決まりがある。
書き写しなので、決まりの側をここへ固定する。

選び方はこちらの設計で、
seedとブロックの中身から直接インデックスを求める。
ブロックが互いに独立することが目的なので、
その独立性もここで表明する。

どちらもずれても例外は出ない。
選択肢の記号がそのままプロンプトへ流れるか、
違う選択肢が選ばれるだけなので、出てきた絵を見ても気付けない。
"""

import pytest
from convert import Node, Prompt
from dynamic import expand, expand_into, sources
from nodedef import NodeDef, Slot, Widget


def test_text_without_choices_is_kept() -> None:
    assert expand("1girl, standing", 0) == "1girl, standing"


def test_one_of_the_options_is_chosen() -> None:
    assert expand("{a|b|c}", 0) in ("a", "b", "c")


def test_every_option_can_be_chosen() -> None:
    # 特定の選択肢が構造的に選ばれないと、
    # プロンプトに書いた選択肢が黙って死ぬ。
    assert {expand("{a|b|c}", seed) for seed in range(50)} == {"a", "b", "c"}


def test_the_same_seed_draws_the_same_option() -> None:
    # 本家は`Math.random`なので揃わない。
    # こちらはseedから決まるので、気に入った1枚を作り直せる。
    assert expand("{a|b|c}", 7) == expand("{a|b|c}", 7)


def test_different_seeds_draw_differently() -> None:
    # 同じ選択肢に固定されるなら`--repeat`で変化が出ない。
    assert 1 < len({expand("{a|b|c|d|e}", seed) for seed in range(20)})


def test_a_block_does_not_depend_on_the_blocks_before_it() -> None:
    # 擬似乱数の列から順に引くとここが崩れる。
    # 前のブロックの選択肢の数が変わるだけで、
    # 後ろのブロックの選択が全部ずれてしまい、
    # 気に入った1枚に候補を足して試すことができなくなる。
    for seed in range(200):
        assert (
            expand("{a|b}, {x|y}", seed)[-1]
            == expand("{a|b|c|d|e|f|g}, {x|y}", seed)[-1]
        )


def test_a_block_does_not_depend_on_whether_another_block_exists() -> None:
    # 先頭へブロックを1つ足しても、後ろの選択は動かない。
    for seed in range(20):
        assert expand("{x|y}", seed) == expand("{a|b}, {x|y}", seed)[-1]


def test_the_same_options_written_twice_draw_separately() -> None:
    # 鍵が中身だけだと必ず揃う。出現回数を混ぜて分ける。
    assert any(expand("{a|b} {a|b}", seed) in ("a b", "b a") for seed in range(20))


def test_the_same_options_in_another_widget_draw_separately() -> None:
    # ポジティブとネガティブに同じ選択肢を書いた時に揃わないようにする。
    assert any(
        expand("{a|b}", seed, salt="4.text") != expand("{a|b}", seed, salt="5.text")
        for seed in range(20)
    )


def test_surrounding_text_is_kept() -> None:
    assert expand("1girl, {standing}, park", 0) == "1girl, standing, park"


def test_multiple_blocks_are_all_expanded() -> None:
    assert expand("{a}, {b}", 0) == "a, b"


def test_nested_blocks_are_expanded() -> None:
    # 内側の`|`は外側の区切りにしない。
    assert expand("{{a|b}}", 0) in ("a", "b")


def test_inner_separator_does_not_split_the_outer_block() -> None:
    # 選択肢が2つに見えるが、外側から見れば1つしかない。
    assert expand("{x{a|b}y}", 0) in ("xay", "xby")


def test_an_empty_option_is_allowed() -> None:
    # 「付けるか付けないか」を書く時の形。
    assert {expand("1girl{, smile|}", seed) for seed in range(50)} == {
        "1girl, smile",
        "1girl",
    }


def test_escaped_braces_are_not_syntax() -> None:
    assert expand(r"\{a|b\}", 0) == "{a|b}"


def test_other_escapes_survive() -> None:
    # `yuuka \(blue_archive\)`のエスケープを壊さない。
    # 外すのは波括弧と縦棒だけである。
    assert expand(r"yuuka \(blue_archive\)", 0) == r"yuuka \(blue_archive\)"


def test_comments_are_stripped() -> None:
    assert expand("{a} // 覚え書き", 0) == "a "


@pytest.mark.parametrize("text", ["{a|b", "{", "\\"])
def test_unterminated_input_does_not_raise(text: str) -> None:
    # 閉じ忘れは書き間違いだが、
    # 例外で止めると生成そのものが失敗する。
    # 本家も末尾までを1つの選択肢として読むので、それに揃える。
    assert isinstance(expand(text, 0), str)


def text_node(dynamic: bool) -> NodeDef:
    return NodeDef(
        slots=(
            Slot(
                widget=Widget(
                    name="text", kind="STRING", choices=None, dynamic=dynamic
                ),
                controls=None,
            ),
        ),
        required=("text",),
    )


TEXT = text_node(dynamic=True)
WILDCARD = text_node(dynamic=False)


def prompt_with(value: str) -> Prompt:
    return Prompt(
        nodes={
            "1": Node(class_type="CLIPTextEncode", title="", inputs={"text": value})
        },
        controls={},
    )


def test_only_dynamic_widgets_are_collected() -> None:
    # `FaceDetailer`の`wildcard`のように`dynamicPrompts`が偽のものがある。
    # 拾うと、UIでは残る記号がコマンドからだけ消える。
    assert sources(prompt_with("{a|b}"), {"CLIPTextEncode": WILDCARD}) == {}


def test_dynamic_widgets_are_collected() -> None:
    found = sources(prompt_with("{a|b}"), {"CLIPTextEncode": TEXT})
    assert found == {("1", "text"): "{a|b}"}


def test_values_without_choices_are_not_collected() -> None:
    # 波括弧を持たない値を通すとコメントの除去だけが効いてしまう。
    # 選択肢を書いていない人が黙って文字を失うのは避ける。
    assert sources(prompt_with("a//b"), {"CLIPTextEncode": TEXT}) == {}


def test_expand_into_writes_back() -> None:
    prompt = prompt_with("{a|b}")
    found = sources(prompt, {"CLIPTextEncode": TEXT})
    applied = expand_into(prompt, found, 0)
    assert prompt.nodes["1"].inputs["text"] in ("a", "b")
    assert applied == {"1.text": prompt.nodes["1"].inputs["text"]}


def test_repeated_expansion_draws_from_the_original() -> None:
    # 書き戻した値には選択肢が残らない。
    # 集めた側から引き直さないと、2回目以降が1回目の結果に固定される。
    prompt = prompt_with("{a|b|c}")
    found = sources(prompt, {"CLIPTextEncode": TEXT})
    drawn: set[object] = set()
    for seed in range(50):
        expand_into(prompt, found, seed)
        drawn.add(prompt.nodes["1"].inputs["text"])
    assert drawn == {"a", "b", "c"}
