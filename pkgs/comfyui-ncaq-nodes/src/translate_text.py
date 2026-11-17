# 指示文を英語へ翻訳するテキストノード。
# WanやQwen-Imageの指示文は英語と中国語が公式サポートのため、
# 日本語で書いた指示をワークフロー内で英語へ変換してから渡す用途。
# 言語は自動判定なので日本語でも英語原文の直接入力でも良い。
# 英語で書いた場合はほぼそのまま通過する。
#
# `context`には何のための文なのかを英語で書く。
# 翻訳モデルが訳語を選ぶ時の参照文脈になり、訳文には含まれない。
# どう効くかは`translate.py`の冒頭に書いてある。
#
# 翻訳に失敗した場合はエラーをログに残した上で原文をそのまま返す。
# 指示文を受け取るモデルは多言語対応なので原文でもある程度は機能するため。
import traceback

from .translate import translate_to_english

# `context`を繋がなかった時の文脈。
# 用途を決め打ちできないノードなので、生成モデル向けの指示文だということだけを伝える。
DEFAULT_CONTEXT = (
    "This is a prompt for a generative AI model "
    "that creates anime-style images or videos."
)

TextInputConfig = tuple[str, dict[str, bool | str]]
InputTypes = dict[str, dict[str, TextInputConfig]]


class TranslateTextToEnglish:
    @classmethod
    def INPUT_TYPES(cls) -> InputTypes:
        return {
            "required": {
                "text": ("STRING", {"multiline": True, "default": ""}),
            },
            # 既存のワークフローは`text`しか持たないので、省略できるようにする。
            "optional": {
                "context": ("STRING", {"multiline": True, "default": DEFAULT_CONTEXT}),
            },
        }

    RETURN_TYPES: tuple[str, ...] = ("STRING",)
    RETURN_NAMES: tuple[str, ...] = ("english_text",)
    FUNCTION: str = "translate"
    CATEGORY: str = "text"

    def translate(self, text: str, context: str = DEFAULT_CONTEXT) -> tuple[str]:
        if not text.strip():
            return ("",)
        try:
            return (translate_to_english(text, context),)
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
