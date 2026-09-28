"""指示文をQwen-Image-2.1向けの英文の編集命令へ書き換えるための、入出力の組み立てと解析。

ComfyUIやtorchに触れないので、
`custom-node/tests/`のpytestからそのままimportできる。

書き換えそのものはQwen-Image-2.1公式の編集指示リライト用モデルPE-I2Iが担う。
PE-I2IはQwen3.5 9Bを公式のシステムプロンプトと回答形式で学習させたもので、
プロンプトと回答形式が重みの一部になっている。
そのためシステムプロンプトは手を加えずに渡し、回答も公式の形式で読む。
形式は公式リポジトリの`prompt_rewrite/pe_core.py`に書かれていて、
思考の後に次のJSONを出す。

    {"rewritten_prompt": "...", "wh_ratio": "", "ratio_follow": "<image1>"}

公式のシステムプロンプトとコードはQwen Research Licenseなので、
このリポジトリには取り込まず、
ノードのderivationがビルド時に公式リポジトリから配置する(`custom-node.nix`)。
ここにある組み立てと解析は、公式リポジトリの`prompt_rewrite/`の説明に合わせて書き起こしたものである。
https://github.com/QwenLM/Qwen-Image-2.1/tree/fb7ae1d1f9611cd91524d03c53c5246b36ac8577
"""

import json
import math
import re
from dataclasses import dataclass
from typing import cast

# Qwen3.5のチャットテンプレートが画像1枚ごとに置くトークン列。
# ComfyUIのトークナイザは`<|image_pad|>`を見つけた順に渡した画像へ差し替える。
VISION_BLOCK = "<|vision_start|><|image_pad|><|vision_end|>"


def build_prompt(system_prompt: str, instruction: str, image_count: int) -> str:
    """PE-I2Iへ渡すチャットをQwen3.5のテンプレートの形で組み立てる。

    ComfyUIのQwen3.5トークナイザは`<|im_start|>`で始まる文字列を受けると、
    組み込みのテンプレートを使わずそのままトークン化する。
    組み込みの方にはsystemの枠が無いので、systemごと自分で組む。

    画像は指示文より前に順番どおりに並べる。
    公式のシステムプロンプトは画像を`<image1>`、`<image2>`と番号で呼ぶので、
    並びを変えると書き換え後の参照が全て別の画像を指す。

    末尾の`<think>\\n`は公式のテンプレートが思考を有効にした時の前置きである。
    PE-I2Iは思考ありで学習されている。
    """
    return (
        f"<|im_start|>system\n{system_prompt}<|im_end|>\n"
        f"<|im_start|>user\n{VISION_BLOCK * image_count}{instruction}<|im_end|>\n"
        "<|im_start|>assistant\n<think>\n"
    )


def answer_section(generated: str) -> str:
    """生成結果から思考を除いた回答の部分を返す。

    前置きの`<think>`はプロンプトの側にあるので、
    生成結果は思考の途中から始まって`</think>`で閉じる。
    閉じていなければ生成が上限で切れたことになり、回答は無い。

    デコードで思考のタグが特殊トークンとして落とされた場合は区切りが見えないので、
    全体を回答として扱う。
    回答のJSONは末尾に出るので、`parse_rewrite`が後ろから探せば思考の中身には当たらない。
    """
    if "</think>" in generated:
        return generated.rsplit("</think>", 1)[1].strip()
    if "<think>" in generated:
        return ""
    return generated.strip()


def json_objects(text: str) -> list[str]:
    """文章中の最も外側の`{...}`を出現順に全て返す。

    貪欲な正規表現で最初の`{`から最後の`}`までを取ると、
    JSONの後ろに波括弧を含む文章が続いた時に範囲が伸びて読めなくなる。
    文字列リテラルの中の波括弧は数えないので、
    書き換え後の指示文が`{`を含んでいても崩れない。
    """
    objects: list[str] = []
    depth = 0
    start = 0
    in_string = False
    escaped = False
    for index, char in enumerate(text):
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char == "{":
            if depth == 0:
                start = index
            depth += 1
        elif char == "}" and 0 < depth:
            depth -= 1
            if depth == 0:
                objects.append(text[start : index + 1])
    return objects


@dataclass(frozen=True)
class Rewrite:
    """PE-I2Iの回答。

    `wh_ratio`と`ratio_follow`は出力のキャンバスの形を決める。
    編集では片方だけに値が入る。
    `ratio_follow`は`<image2>`のように入力画像を指し、その画像の比率を引き継ぐ。
    `wh_ratio`は`16:9`のような比率で、
    元の画面を編集するのではなく新しい構図を作る指示の時に入る。
    公式は、これを無視して元画像の比率で描くと書き換えの一部を捨てることになると明言している。
    """

    prompt: str
    wh_ratio: str
    ratio_follow: str


def text_field(fields: dict[str, object], key: str) -> str:
    """文字列の欄を取り出す。無いか文字列でなければ空文字列にする。"""
    value = fields.get(key)
    return value.strip() if isinstance(value, str) else ""


def parse_rewrite(generated: str) -> Rewrite:
    """PE-I2Iの生成結果から回答を取り出す。

    回答のJSONは末尾に出るので、候補を後ろから順に試す。
    公式の実装に倣い、学習データの一部にあった綴り違いの`rewrited_prompt`も受け付ける。

    期待した形でなければ例外にする。
    呼び出し側が翻訳へ回すか原文へ倒すかを決めるので、
    ここでは倒さずに落とす。
    """
    answer = answer_section(generated)
    if not answer:
        raise ValueError("PE-I2I stopped before finishing its thinking")
    for candidate in reversed(json_objects(answer)):
        try:
            parsed: object = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if not isinstance(parsed, dict):
            continue
        # `isinstance`だけでは要素の型が不明なままで、
        # 取り出した先を型検査が見てくれない。
        # JSONのオブジェクトの値は何であってもよいので`object`へ寄せる。
        fields = cast(dict[str, object], parsed)
        prompt = " ".join(
            (
                text_field(fields, "rewritten_prompt")
                or text_field(fields, "rewrited_prompt")
            ).split()
        )
        if prompt:
            return Rewrite(
                prompt=prompt,
                wh_ratio=text_field(fields, "wh_ratio"),
                ratio_follow=text_field(fields, "ratio_follow"),
            )
    raise ValueError("PE-I2I returned no rewritten_prompt")


# 公式の比率ごとの生成解像度。
# 公式READMEがパイプラインへ渡す例に載せている表で、どれもネイティブ2Kの約4MPになる。
PRESET_RESOLUTION = 2048
PRESET_SIZES: dict[str, tuple[int, int]] = {
    "1:1": (2048, 2048),
    "4:3": (2400, 1792),
    "3:4": (1792, 2400),
    "3:2": (2528, 1696),
    "2:3": (1696, 2528),
    "16:9": (2752, 1536),
    "9:16": (1536, 2752),
}


def round_to_32(value: float) -> int:
    """32の倍数へ丸める。32未満にはしない。"""
    return max(32, round(value / 32) * 32)


def fit_to_resolution(width: int, height: int, resolution: int) -> tuple[int, int]:
    """比率を保ったまま総画素を`resolution`の2乗へ揃えた32の倍数の寸法を返す。

    `TextEncodeQwenImage21`が参照画像を揃える式と同じにする。
    1枚目の画像に従う時に、あちらが作る空のlatentと寸法が一致する。
    """
    ratio = width / height
    return (
        round_to_32(math.sqrt(resolution * resolution * ratio)),
        round_to_32(math.sqrt(resolution * resolution / ratio)),
    )


def preset_size(wh_ratio: str, resolution: int) -> tuple[int, int] | None:
    """`wh_ratio`に対応する寸法を返す。読めなければNoneを返す。

    公式の表にある比率は表の寸法を`resolution`に合わせて縮尺する。
    表に無い比率でも`5:4`の形で読めれば同じ総画素へ揃える。
    """
    preset = PRESET_SIZES.get(wh_ratio)
    if preset is not None:
        scale = resolution / PRESET_RESOLUTION
        return round_to_32(preset[0] * scale), round_to_32(preset[1] * scale)
    matched = re.fullmatch(r"\s*(\d+)\s*:\s*(\d+)\s*", wh_ratio)
    if matched is None:
        return None
    width, height = int(matched[1]), int(matched[2])
    if width == 0 or height == 0:
        return None
    return fit_to_resolution(width, height, resolution)


def followed_image(ratio_follow: str, image_count: int) -> int | None:
    """`ratio_follow`が指す画像の0始まりの番号を返す。渡した画像を指していなければNoneを返す。"""
    matched = re.fullmatch(r"\s*<image(\d+)>\s*", ratio_follow)
    if matched is None:
        return None
    index = int(matched[1]) - 1
    return index if 0 <= index < image_count else None


def canvas_size(
    rewrite: Rewrite | None, image_sizes: list[tuple[int, int]], resolution: int
) -> tuple[int, int]:
    """出力のキャンバスの幅と高さを決める。

    `image_sizes`は渡した画像の幅と高さを、指示文の`<image1>`からの順に並べたものである。
    `rewrite`がNoneなのは書き換えに失敗した時で、
    指示文が画像の比率について何も言っていないので1枚目に従う。
    回答の`ratio_follow`や`wh_ratio`が読めない時も同じく1枚目に従う。
    """
    if rewrite is not None:
        followed = followed_image(rewrite.ratio_follow, len(image_sizes))
        if followed is not None:
            return fit_to_resolution(*image_sizes[followed], resolution)
        preset = preset_size(rewrite.wh_ratio, resolution)
        if preset is not None:
            return preset
    if image_sizes:
        return fit_to_resolution(*image_sizes[0], resolution)
    return round_to_32(resolution), round_to_32(resolution)
