"""指示文をQwen-Image-Edit向けの英文の編集命令へ書き換えるモジュール。

ComfyUIやtorchに触れないので、
`custom-node/tests/`のpytestからそのままimportできる。

`EDIT_SYSTEM_PROMPT`はQwen公式のリライト実装から一字一句そのまま持ってきたものである。
Qwen-ImageはApache License 2.0で公開されている。
https://github.com/QwenLM/Qwen-Image/blob/main/src/examples/tools/prompt_utils.py

公式の`polish_edit_prompt`は指示文と一緒に画像もVLへ渡す。
指示文だけを整えるのではなく、画像を見て対象を特定して書き下すのが本来の使い方で、
`TextEncodeQwenImageEditPlus`がVLへ渡す画像を総画素384*384まで落とすことへの、
前段からの補いになっている。
"""

import json
from pathlib import Path
from typing import cast

# 公式のリライト規則そのもの。
# Markdownとして書かれているので別ファイルへ置く。
# Pythonの文字列として埋めると、
# Markdownの改行を表す行末の2スペースがformatterに落とされて意味が変わる。
EDIT_SYSTEM_PROMPT = (
    (Path(__file__).with_name("edit-system-prompt.md")).read_text().strip()
)


def build_messages(
    instruction: str, image: str | None
) -> list[dict[str, str | list[str]]]:
    """`/api/chat`へ渡すメッセージを組み立てる。

    公式の`edit_api`はsystemに汎用の一文しか置かず、
    `EDIT_SYSTEM_PROMPT`をuserの本文へ連結している。
    ここではそれを分けてsystemへ載せる。
    チャットテンプレートのsystemスロットへ入る方が規則の遵守が安定し、
    指示文の側から規則を上書きすることもできなくなる。

    実測でも書き換えの質と所要時間は連結した場合と変わらなかった。
    """
    messages: list[dict[str, str | list[str]]] = [
        {"role": "system", "content": EDIT_SYSTEM_PROMPT},
        # 末尾の`Rewritten Prompt:`は公式の組み立てから引き継ぐ。
        # 応答をJSONから書き出させる呼び水になっている。
        {"role": "user", "content": f"User Input: {instruction}\n\nRewritten Prompt:"},
    ]
    if image is not None:
        messages[-1]["images"] = [image]
    return messages


def rewritten_text(response: str) -> str:
    """モデルの応答から書き換え後の指示文を取り出す。

    公式は`{"Rewritten": "..."}`のJSONを期待する。
    コードブロックで包んで返してくることがあるので剥がしてから読む。

    期待した形でなければ例外にする。
    呼び出し側が元の指示文へ倒すか翻訳へ回すかを決めるので、
    ここでは倒さずに落とす。
    """
    stripped = response.strip()
    if stripped.startswith("```"):
        # ```json のような言語指定の行と閉じの``` を落とす。
        lines = stripped.splitlines()
        if lines[-1].strip() == "```":
            lines = lines[:-1]
        stripped = "\n".join(lines[1:]).strip()
    try:
        parsed: object = json.loads(stripped)
    except json.JSONDecodeError as error:
        raise ValueError(f"Ollama returned a non-JSON rewrite: {error}") from error
    if not isinstance(parsed, dict):
        raise ValueError("Ollama returned a JSON value that is not an object")
    # `isinstance`だけでは要素の型が不明なままで、
    # 取り出した先を型検査が見てくれない。
    # JSONのオブジェクトの値は何であってもよいので`object`へ寄せる。
    rewritten = cast(dict[str, object], parsed).get("Rewritten")
    if not isinstance(rewritten, str):
        raise ValueError("Ollama returned no Rewritten string")
    rewritten = " ".join(rewritten.split())
    if not rewritten:
        raise ValueError("Ollama returned an empty rewrite")
    return rewritten
