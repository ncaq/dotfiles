# 日本語の編集指示を、Qwen-Image-2.1向けの英文の編集命令へ書き換えるノード。
#
# qwen-editワークフローの前段には元々TranslateTextToEnglishを置いていた。
# あれはGoogle翻訳へ投げるだけで、訳文の構造は元の文のままである。
# ノード自体は`custom-node/translate-text/`に残っていて、
# anime-videoとanime-video-extendのワークフローでは今も使っている。
# Qwen公式は翻訳ではなくリライトを前段に置いていて、
# 対象と属性と位置を明示し、変えない部分まで書き下した英文へ組み直す。
#
# Qwen-Image-Edit 2511の頃はOllamaの汎用モデルへ公式の規則を渡して書き換えていた。
# 2.1では公式がその役割のためにQwen3.5 9Bをfine-tuneしたPE-I2Iを配布しているので、
# それをComfyUIの中でCLIPとして読み、文章生成させる。
# 指示文での画像の呼び方が`<image1>`に変わったので、
# 2511向けの規則をそのまま使い続けることはできない。
# ComfyUIの外へ出ないので、
# 以前のようにComfyUIの重みを全て降ろしてOllamaの27Bを読み直す往復も無くなった。
#
# 画像も一緒に渡す。
# 「この子の服装を変えて」のような曖昧な指示でも、
# 画像を見て実際に着ている服を指した指示文に書き下せる。
#
# 失敗しても生成そのものは続けたいので、2段階で退避する。
# 書き換えに失敗すればGoogle翻訳で英語にし、
# それも駄目なら原文をそのまま通す。
# どちらもstderrへ理由を残す。
#
# ComfyUI本体は型注釈をほとんど持たないので、
# CLIPのメソッドの型が決まらず、torchのスタブにも不明な部分がある。
# strictのUnknown系はこれらに触れる式を全て挙げてしまう。
# 上流に型が付くまではこのファイルでだけ落とす。
# pyright: reportUnknownArgumentType=none
# pyright: reportUnknownMemberType=none
# pyright: reportUnknownVariableType=none

import math
import sys
import traceback
from pathlib import Path
from typing import Any

import comfy.utils
import torch

from .rewrite import Rewrite, build_prompt, canvas_size, parse_rewrite
from .translate import translate_to_english

# 公式のシステムプロンプト。
# Qwen Research Licenseなのでリポジトリには置かず、
# ノードのderivationがビルド時に公式リポジトリから配置する(`custom-node.nix`)。
SYSTEM_PROMPT_PATH = Path(__file__).with_name("system_prompt_edit.txt")

# 1枚あたりの画素数の上限。
# 公式の`pe_core.py`が学習時に合わせて入力画像を縮める上限と同じ値にする。
MAX_IMAGE_PIXELS = 1024 * 1024

# 生成するトークン数の上限。
# 公式の`pe_core.py`の編集用の既定値に揃える。
# 思考が上限で切れると回答が無くなり翻訳へ退避することになるので、
# テキストの生成でしかない分を削って公式から外れる理由は無い。
MAX_NEW_TOKENS = 24000


def prepare_image(image: torch.Tensor) -> torch.Tensor:
    """先頭の1枚をRGBにして、総画素が`MAX_IMAGE_PIXELS`を超えれば縮める。

    IMAGEは4チャンネルのこともあるのでアルファは落とす。
    公式もPillowで`convert("RGB")`してから渡している。
    """
    picture = image[:1, ..., :3]
    height, width = picture.shape[1], picture.shape[2]
    if height * width <= MAX_IMAGE_PIXELS:
        return picture
    scale = math.sqrt(MAX_IMAGE_PIXELS / (height * width))
    resized = comfy.utils.common_upscale(
        picture.movedim(-1, 1),
        max(1, int(width * scale)),
        max(1, int(height * scale)),
        "lanczos",
        "disabled",
    )
    return resized.movedim(1, -1)


def request_rewrite(
    clip: Any, text: str, images: list[torch.Tensor], seed: int
) -> Rewrite:
    """PE-I2Iで書き換えた回答を返す。"""
    system_prompt = SYSTEM_PROMPT_PATH.read_text(encoding="utf-8").strip()
    prompt = build_prompt(system_prompt, text, len(images))
    tokens = clip.tokenize(prompt, images=images, min_length=1)
    # サンプリングの設定は公式の`pe_core.py`の編集用の値そのままである。
    # 公式は用途ごとに値が違う点を強調していて、
    # 特にpresence_penaltyは生成用の1.5に対して編集用は0になる。
    generated_ids = clip.generate(
        tokens,
        do_sample=True,
        max_length=MAX_NEW_TOKENS,
        temperature=1.0,
        top_k=20,
        top_p=0.95,
        min_p=0.0,
        repetition_penalty=1.0,
        presence_penalty=0.0,
        seed=seed,
    )
    return parse_rewrite(clip.decode(generated_ids))


class RewriteEditPrompt:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, object]:
        return {
            "required": {
                "text": ("STRING", {"multiline": True, "default": ""}),
                # PE-I2IのファイルをCLIPLoaderで読んだもの。
                "clip": ("CLIP",),
                # 公式どおりtemperature 1.0でサンプリングするので、
                # 同じ指示でも書き換えは毎回揺れる。
                # 生成のseedとは分けて固定値にしておくと、
                # 生成のseedだけ変える連打で書き換えまでやり直さずに済む。
                "seed": (
                    "INT",
                    {"default": 0, "min": 0, "max": 0xFFFFFFFFFFFFFFFF},
                ),
                # 出力の寸法を揃える総画素の平方根。
                # `TextEncodeQwenImage21`のresolutionと同じ値を渡す。
                # 1枚目に従う時にあちらが作るlatentと同じ寸法になる。
                "resolution": (
                    "INT",
                    {"default": 2048, "min": 32, "max": 4096, "step": 32},
                ),
            },
            # 番号は指示文の`<image1>`、`<image2>`に対応する。
            # 繋がっていない枠は詰めて数えるので、
            # 3枚目だけ繋ぐとそれが`<image2>`になる。
            # エンコード側の`TextEncodeQwenImage21`も同じ数え方をする。
            "optional": {
                "image1": ("IMAGE",),
                "image2": ("IMAGE",),
                "image3": ("IMAGE",),
            },
        }

    # 指示文に加えて、PE-I2Iが決めた出力のキャンバスの寸法を返す。
    # 空のlatentをこの寸法で作ってサンプリングする。
    RETURN_TYPES: tuple[str, str, str] = ("STRING", "INT", "INT")
    RETURN_NAMES: tuple[str, str, str] = ("english_text", "width", "height")
    FUNCTION: str = "rewrite"
    CATEGORY: str = "utils"

    def rewrite(
        self,
        text: str,
        clip: Any,
        seed: int,
        resolution: int,
        image1: torch.Tensor | None = None,
        image2: torch.Tensor | None = None,
        image3: torch.Tensor | None = None,
    ) -> tuple[str, int, int]:
        images = [image for image in (image1, image2, image3) if image is not None]
        image_sizes = [(int(image.shape[2]), int(image.shape[1])) for image in images]
        if not text.strip():
            return ("", *canvas_size(None, image_sizes, resolution))
        try:
            rewrite = request_rewrite(
                clip, text, [prepare_image(image) for image in images], seed
            )
            width, height = canvas_size(rewrite, image_sizes, resolution)
            # キャンバスの決め方は指示によって変わるので、何に従ったのかを残す。
            # 出力の寸法が編集する画像と違う時に、理由をジャーナルから追えるようにする。
            print(
                f"[RewriteEditPrompt] ratio_follow={rewrite.ratio_follow!r}"
                f" wh_ratio={rewrite.wh_ratio!r} -> {width}x{height}",
                file=sys.stderr,
            )
            return (rewrite.prompt, width, height)
        except Exception:
            print(
                f"[RewriteEditPrompt] PE-I2Iでのリライトに失敗したので翻訳へ退避します:\n{traceback.format_exc()}",
                file=sys.stderr,
            )
        size = canvas_size(None, image_sizes, resolution)
        try:
            return (translate_to_english(text), *size)
        except Exception as error:
            print(
                f"[RewriteEditPrompt] 翻訳にも失敗したので原文をそのまま使います: {error}",
                file=sys.stderr,
            )
        return (text, *size)


NODE_CLASS_MAPPINGS: dict[str, type[RewriteEditPrompt]] = {
    "RewriteEditPrompt": RewriteEditPrompt,
}

NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {
    "RewriteEditPrompt": "Rewrite Edit Prompt",
}
