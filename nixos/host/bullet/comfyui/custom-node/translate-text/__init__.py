# 指示文を英語へ翻訳するテキストノード。
# Qwen-Image-Editの指示文は英語と中国語が公式サポートのため、
# 日本語で書いた指示をワークフロー内で英語へ変換してから渡す用途。
# 言語は自動判定なので日本語でも英語原文の直接入力でも良い。
# 英語で書いた場合は実質そのまま通過する。
#
# ComfyUIのPython環境に既に入っているrequestsだけで動くように、
# Google翻訳の非公式gtxエンドポイントを使う。
# 翻訳に失敗した場合はエラーをログに残した上で原文をそのまま返す。
# Qwen2.5-VLは多言語対応なので原文でもある程度は機能するため。
import traceback
from typing import cast

import requests


TextInputConfig = tuple[str, dict[str, bool | str]]
InputTypes = dict[str, dict[str, TextInputConfig]]


def non_empty_list(value: object, message: str) -> list[object]:
    """JSONの空でない配列を、要素の型が分かる形で取り出す。

    `isinstance(value, list)`だけでは要素の型が不明なままになり、
    取り出した先を型検査が見てくれない。
    JSONの配列の要素は何であってもよいので`object`へ寄せる。
    """
    if not isinstance(value, list) or not value:
        raise ValueError(message)
    return cast(list[object], value)


def translated_text(payload: object) -> str:
    response_items = non_empty_list(
        payload, "Google Translate returned an invalid response"
    )
    segments = non_empty_list(
        response_items[0], "Google Translate returned invalid segments"
    )

    translated_segments: list[str] = []
    for segment in segments:
        segment_items = non_empty_list(
            segment, "Google Translate returned an invalid segment"
        )
        text = segment_items[0]
        if not isinstance(text, str):
            raise ValueError("Google Translate returned non-text translation data")
        translated_segments.append(text)
    return "".join(translated_segments)


class TranslateTextToEnglish:
    @classmethod
    def INPUT_TYPES(cls) -> InputTypes:
        return {
            "required": {
                "text": ("STRING", {"multiline": True, "default": ""}),
            }
        }

    RETURN_TYPES: tuple[str, ...] = ("STRING",)
    RETURN_NAMES: tuple[str, ...] = ("english_text",)
    FUNCTION: str = "translate"
    CATEGORY: str = "text"

    def translate(self, text: str) -> tuple[str]:
        if not text.strip():
            return ("",)
        try:
            response = requests.get(
                "https://translate.googleapis.com/translate_a/single",
                params={
                    "client": "gtx",
                    "sl": "auto",
                    "tl": "en",
                    "dt": "t",
                    "q": text,
                },
                timeout=10,
            )
            response.raise_for_status()
            return (translated_text(response.json()),)
        except Exception:
            print("[translate-text] translation failed, using original text")
            traceback.print_exc()
            return (text,)


NODE_CLASS_MAPPINGS: dict[str, type[TranslateTextToEnglish]] = {
    "TranslateTextToEnglish": TranslateTextToEnglish,
}

NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {
    "TranslateTextToEnglish": "Translate Text to English",
}
