# 指示文を英語へ翻訳するテキストノード。
# Qwen-Image-Editの指示文は英語と中国語が公式サポートのため、
# 日本語で書いた指示をワークフロー内で英語へ変換してから渡す用途。
# 言語は自動判定なので日本語でも英語原文の直接入力でも良い。
# 英語で書いた場合は実質そのまま通過する。
#
# 翻訳に失敗した場合はエラーをログに残した上で原文をそのまま返す。
# Qwen2.5-VLは多言語対応なので原文でもある程度は機能するため。
import traceback

from .translate import translate_to_english


TextInputConfig = tuple[str, dict[str, bool | str]]
InputTypes = dict[str, dict[str, TextInputConfig]]


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
            return (translate_to_english(text),)
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
