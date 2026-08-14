# 指示文を英語へ翻訳するモジュール。
#
# ComfyUIのPython環境に既に入っているrequestsだけで動くように、
# Google翻訳の非公式gtxエンドポイントを使う。
#
# レスポンスは文字列を深く入れ子にした配列で、
# 形が違えばどこで壊れているのか分かるように`ValueError`にする。
# 翻訳できなかった時に原文へ倒すかどうかは呼び出し側の判断なので、
# ここでは倒さずに落とす。
#
# 使う側のノードディレクトリへ`../translate.py`へのsymlinkを置き、
# ノードのderivationが`cp -rL`で実体化して配る。
# `from .translate import translate_to_english`と相対importで使う。
from typing import cast

import requests


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
    """gtxエンドポイントのレスポンスから訳文を組み立てる。"""
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


def translate_to_english(text: str) -> str:
    """テキストを英語へ翻訳する。

    元の言語は自動判定なので、日本語でも英語の原文でもそのまま渡してよい。
    """
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
    translated = translated_text(response.json())
    if not translated:
        raise ValueError("Google Translate returned an empty translation")
    return translated
