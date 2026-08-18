# 日本語の編集指示を、Qwen-Image-Edit向けの英文の編集命令へ書き換えるノード。
#
# 以前ここに置いていたTranslateTextToEnglishはGoogle翻訳へ投げるだけで、
# 訳文の構造は元の文のままだった。
# Qwen公式は翻訳ではなくリライトを前段に置いていて、
# タスク種別ごとの規則に沿って対象と属性と位置を明示した英文へ組み直す。
# その規則そのものが`rewrite.py`の`EDIT_SYSTEM_PROMPT`である。
#
# 公式は画像も一緒に渡すので、ここでも渡す。
# `TextEncodeQwenImageEditPlus`がVLへ渡す画像は総画素384*384まで縮むため、
# 小さい対象や複数ある対象を指示文の側で特定しておく意味が大きい。
# 実測でも「この子の服装を変えて」に対して、
# 画像なしは一般論へ流れたのに対し、
# 画像ありは実際に着ている紺のパーカーを指して書き換えた。
#
# 失敗しても生成そのものは続けたいので、2段階で退避する。
# Ollamaへ届かなければ従来どおりGoogle翻訳で英語にし、
# それも駄目なら原文をそのまま通す。
# どちらもstderrへ理由を残す。
#
# ComfyUI本体は型注釈をほとんど持たないので、
# `comfy.model_management.unload_all_models`の型が決まらず、
# torchやPillowのスタブにも不明な部分がある。
# strictのUnknown系はこれらに触れる式を全て挙げてしまう。
# 上流に型が付くまではこのファイルでだけ落とす。
# pyright: reportUnknownArgumentType=none
# pyright: reportUnknownMemberType=none
# pyright: reportUnknownVariableType=none

import base64
import io
import os
import sys

import comfy.model_management
import requests
import torch
from PIL import Image

from .rewrite import build_prompt, rewritten_text
from .translate import translate_to_english

# 接続先を渡す環境変数。`nixos/host/bullet/comfyui/ollama.nix`が設定する。
# Ollamaのコンテナへ直接繋ぐのではなくホスト側のsocketへ繋ぐので、
# 止まっていればオンデマンドで起動する。
#
# 既定値は置かない。
# コンテナの中で127.0.0.1を叩いても何も居らず、
# 設定が届いていないことを接続失敗として遅れて知るだけになる。
URL_VARIABLE = "COMFYUI_OLLAMA_URL"

# VLへ渡す画像の最長辺。
# 大きいほどprefillのトークンが増えるが、
# 1280程度なら実測で生成時間はほぼ変わらず、対象の判別には十分だった。
MAX_IMAGE_SIDE = 1280

# モデルのロードと生成を待つ上限。
# 実測ではVRAMが空いていれば27Bで5秒、
# ComfyUIと取り合って層がCPUへ溢れた最悪の場合で30秒だった。
# 桁で外れたら待ち続けるより翻訳へ退避した方がよい。
TIMEOUT_SECONDS = 120


def encode_image(image: torch.Tensor) -> str:
    """先頭の1枚を最長辺`MAX_IMAGE_SIDE`まで縮めてPNGのbase64にする。

    アルファは落とす。
    IMAGEは4チャンネルのこともあり、
    そのまま渡すとRGB指定の`Image.fromarray`が例外にする。
    """
    array = (
        image[0, ..., :3]
        .detach()
        .clamp(0, 1)
        .mul(255)
        .round()
        .to(torch.uint8)
        .cpu()
        .numpy()
    )
    picture = Image.fromarray(array, "RGB")
    picture.thumbnail((MAX_IMAGE_SIDE, MAX_IMAGE_SIDE), Image.Resampling.LANCZOS)
    buffer = io.BytesIO()
    picture.save(buffer, format="PNG")
    return base64.b64encode(buffer.getvalue()).decode()


def request_rewrite(model: str, text: str, image: str | None) -> str:
    """Ollamaへ問い合わせて書き換え後の指示文を返す。

    接続先もモデル名も外から与えられるものなので、
    欠けていれば何が足りないのか分かる形で落とす。
    呼び出し側がそれを見て翻訳へ退避する。
    """
    url = os.environ.get(URL_VARIABLE)
    if not url:
        raise ValueError(f"{URL_VARIABLE} is not set")
    if not model:
        raise ValueError("No Ollama model specified")
    payload: dict[str, object] = {
        "model": model,
        "prompt": build_prompt(text),
        "stream": False,
        # 思考させても書き換えの質は上がらず、待ち時間だけ伸びる。
        "think": False,
        # 応答を返した直後にモデルを降ろす。
        # `OLLAMA_KEEP_ALIVE`はCUDAのホストで5分なので、
        # 指定しないとその間VRAMを掴んだままComfyUIを圧迫する。
        "keep_alive": 0,
        "options": {"num_ctx": 8192, "temperature": 0.2},
    }
    if image is not None:
        payload["images"] = [image]
    response = requests.post(
        f"{url}/api/generate", json=payload, timeout=TIMEOUT_SECONDS
    )
    response.raise_for_status()
    return rewritten_text(response.json()["response"])


class RewriteEditPrompt:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, object]:
        return {
            "required": {
                "text": ("STRING", {"multiline": True, "default": ""}),
                # モデル名の既定値は置かない。
                # ワークフローがOllamaへ載せるモデルの定義から渡すので、
                # ここにも書くと二重の情報源になって片方が黙って古くなる。
                "model": ("STRING", {"default": ""}),
                "free_comfyui_vram": ("BOOLEAN", {"default": True}),
            },
            "optional": {"image": ("IMAGE",)},
        }

    RETURN_TYPES: tuple[str] = ("STRING",)
    RETURN_NAMES: tuple[str] = ("english_text",)
    FUNCTION: str = "rewrite"
    CATEGORY: str = "utils"

    def rewrite(
        self,
        text: str,
        model: str,
        free_comfyui_vram: bool,
        image: torch.Tensor | None = None,
    ) -> tuple[str]:
        if not text.strip():
            return ("",)
        if free_comfyui_vram:
            # ComfyUIが載せたままの重みとリライトのモデルがVRAMを取り合うと、
            # 層がCPUへ溢れて実測で5倍以上遅くなる。
            # 降ろす分の載せ直しは実測8秒程度で、待たされる合計はそれでも短い。
            # このノードは指示文が変わった時しか再実行されないので、
            # seedだけ変える連打ではここも通らない。
            comfy.model_management.unload_all_models()
        try:
            encoded = encode_image(image) if image is not None else None
            return (request_rewrite(model, text, encoded),)
        except Exception as error:
            print(
                f"[RewriteEditPrompt] Ollamaでのリライトに失敗したので翻訳へ退避します: {error}",
                file=sys.stderr,
            )
        try:
            return (translate_to_english(text),)
        except Exception as error:
            print(
                f"[RewriteEditPrompt] 翻訳にも失敗したので原文をそのまま使います: {error}",
                file=sys.stderr,
            )
        return (text,)


NODE_CLASS_MAPPINGS: dict[str, type[RewriteEditPrompt]] = {
    "RewriteEditPrompt": RewriteEditPrompt,
}

NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {
    "RewriteEditPrompt": "Rewrite Edit Prompt",
}
