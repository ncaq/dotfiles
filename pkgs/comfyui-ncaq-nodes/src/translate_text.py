# 指示文を英語へ翻訳するテキストノード。
# WanやQwen-Imageの指示文は英語と中国語が公式サポートのため、
# 日本語で書いた指示をワークフロー内で英語へ変換してから渡す用途。
# 言語は自動判定なので日本語でも英語原文の直接入力でも良い。
# 英語で書いた場合はほぼそのまま通過する。
#
# `context`では何のための文なのかを選ぶ。
# 翻訳モデルが訳語を選ぶ時の参照文脈になり、訳文には含まれない。
# 選べる用途と、自由な文を書かせない理由は`translate.py`に書いてある。
#
# 翻訳に失敗した場合は原文で続けずに、ノードのエラーにする。
# 原文で続けると、翻訳が効いていないことに生成結果を見るまで気付けない。
from .translate import CONTEXTS, translate_to_english

# `context`を繋がなかった時の用途。
# 用途を決め打ちできないノードなので、生成モデル向けの指示文だということだけを伝える。
DEFAULT_CONTEXT = "generic"

InputTypes = dict[str, dict[str, tuple[str | list[str], dict[str, bool | str]]]]


class TranslateTextToEnglish:
    @classmethod
    def INPUT_TYPES(cls) -> InputTypes:
        return {
            "required": {
                "text": ("STRING", {"multiline": True, "default": ""}),
            },
            # 既存のワークフローは`text`しか持たないので、省略できるようにする。
            "optional": {
                "context": (list(CONTEXTS), {"default": DEFAULT_CONTEXT}),
            },
        }

    RETURN_TYPES: tuple[str, ...] = ("STRING",)
    RETURN_NAMES: tuple[str, ...] = ("english_text",)
    FUNCTION: str = "translate"
    CATEGORY: str = "text"

    def translate(self, text: str, context: str = DEFAULT_CONTEXT) -> tuple[str]:
        if not text.strip():
            return ("",)
        return (translate_to_english(text, context),)


NODE_CLASS_MAPPINGS: dict[str, type[TranslateTextToEnglish]] = {
    "TranslateTextToEnglish": TranslateTextToEnglish,
}

NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {
    "TranslateTextToEnglish": "Translate Text to English",
}
