# 指示文を英語へ翻訳するモジュール。
#
# 同じコンテナで動く`llama-server`のPLaMo 3 Translateへ投げる。
# サーバの設定は`nixos/host/bullet/comfyui/translate.nix`にある。
#
# PLaMo 3 Translateのチャットテンプレートは、
# systemメッセージの本文を訳さない参照文脈として扱う。
# 何のための文なのかを英語で渡すと訳語の選び方が変わり、
# 文脈が無いと`jito eyes`と音訳された「ジト目」が`half-lidded eyes`になった。
#
# 訳す先は英語に固定する。
# 省略するとモデルが言語を判定して逆へ訳すので、英語で書いた指示が日本語になる。
#
# 翻訳できなかった時は例外にして、呼び出したノードのエラーにする。
# 原文で続けると、翻訳が効いていないことに生成結果を見るまで気付けない。
import functools
import http.client
import json
import os
from typing import Literal, cast

# 1回の翻訳を待つ秒数。CPUで推論するので長い指示では数秒かかる。
TIMEOUT_SECONDS = 60

# 翻訳モデルへ渡す参照文脈を、用途の名前から引く表。
#
# 呼び出し側には自由な文を書かせず、ここにある名前から選ばせる。
# 文脈はsystemメッセージになるので、
# ワークフローから任意の文を渡せると訳文を好きな方向へ誘導できてしまう。
#
# 名前を型にしておくと、固定の名前を渡す呼び出し側の打ち間違いを型検査が拾う。
ContextName = Literal["generic", "video", "image-edit", "image-edit-to-video"]

CONTEXTS: dict[ContextName, str] = {
    "generic": (
        "This is a prompt for a generative AI model "
        "that creates anime-style images or videos."
    ),
    "video": (
        "This is a prompt for an AI video generation model. "
        "It describes the motion in an anime-style video clip."
    ),
    "image-edit": (
        "This is an instruction for an AI image editing model "
        "that edits an anime-style illustration of characters."
    ),
    "image-edit-to-video": (
        "This is an instruction for AI models that edit an anime-style image "
        "and then animate it into a video clip."
    ),
}


def request_body(text: str, reference: str) -> dict[str, object]:
    """`/v1/chat/completions`へ送る本体を組み立てる。

    `reference`は参照文脈の英文そのもので、用途の名前ではない。
    """
    return {
        "messages": [
            {"role": "system", "content": reference},
            {"role": "user", "content": text},
        ],
        "chat_template_kwargs": {"target_lang": "en"},
        # 同じ指示は同じ訳文にして、`lru_cache`が返す訳文と訳し直した結果を揃える。
        "temperature": 0,
    }


def non_empty_list(value: object, message: str) -> list[object]:
    """JSONの空でない配列を、要素の型が分かる形で取り出す。

    `isinstance(value, list)`だけでは要素の型が不明なままになり、
    取り出した先を型検査が見てくれない。
    JSONの配列の要素は何であってもよいので`object`へ寄せる。
    """
    if not isinstance(value, list) or not value:
        raise ValueError(message)
    return cast(list[object], value)


def json_object(value: object, message: str) -> dict[str, object]:
    """JSONのオブジェクトを、値の型が分かる形で取り出す。"""
    if not isinstance(value, dict):
        raise ValueError(message)
    return cast(dict[str, object], value)


def translated_text(payload: object) -> str:
    """`/v1/chat/completions`のレスポンスから訳文を取り出す。

    形が違えばどこで壊れているのか分かるように`ValueError`にする。
    """
    response = json_object(payload, "llama-server returned an invalid response")
    choices = non_empty_list(
        response.get("choices"), "llama-server returned invalid choices"
    )
    choice = json_object(choices[0], "llama-server returned an invalid choice")
    # 訳文が上限で切れた時は`length`になる。
    # 途中までの訳は使わずに失敗にする。
    finish_reason = choice.get("finish_reason")
    if finish_reason != "stop":
        raise ValueError(f"llama-server stopped with {finish_reason!r}")
    message = json_object(
        choice.get("message"), "llama-server returned an invalid message"
    )
    content = message.get("content")
    if not isinstance(content, str):
        raise ValueError("llama-server returned non-text translation data")
    translated = content.strip()
    if not translated:
        raise ValueError("llama-server returned an empty translation")
    return translated


# 同じ指示のままseedだけ変えて生成を試す時に、訳し直さずに済ませる。
# ComfyUIは入力の変わらないノードの出力を使い回すが、
# ノードの中から呼ぶ翻訳は、seedが変わるたびに走り直す。
# `temperature`が0なので、同じ引数の訳文は同じになる。
# 例外は覚えないので、失敗した翻訳は次の呼び出しでやり直す。
@functools.lru_cache(maxsize=256)
def request_translation(text: str, reference: str) -> str:
    """参照文脈の英文を付けて、翻訳サーバへテキストを訳させる。"""
    body = json.dumps(request_body(text, reference))
    # `[::1]:8189`のようなホストとポート。
    # スキームはここで固定して、平文のHTTP以外へは繋がない。
    authority = os.environ["PLAMO_TRANSLATE_AUTHORITY"]
    connection = http.client.HTTPConnection(authority, timeout=TIMEOUT_SECONDS)
    try:
        connection.request(
            "POST",
            "/v1/chat/completions",
            body=body,
            headers={"Content-Type": "application/json"},
        )
        response = connection.getresponse()
        response_body = response.read()
    finally:
        connection.close()
    if response.status != http.client.OK:
        # 本体は例外へ入れない。
        # サーバが入力をそのまま含めて返すと、指示文がログへ出てしまう。
        # 拒否の理由は`llama-server`が自分のログへ出すので、
        # 同じコンテナのjournal(`machine-log comfyui`)で追える。
        raise RuntimeError(
            f"llama-server returned {response.status} ({len(response_body)} bytes)"
        )
    return translated_text(json.loads(response_body))


def translate_to_english(text: str, context: ContextName) -> str:
    """テキストを英語へ翻訳する。

    `context`は`CONTEXTS`にある用途の名前で、
    何のための文なのかを翻訳モデルへ伝える。

    元の言語は自動判定なので、日本語でも英語の原文でもそのまま渡してよい。
    """
    # `lru_cache`は包んだ関数の引数の型を消すので、型のある入口をここに分けている。
    #
    # 表に無い名前は、サーバへ投げる前に`KeyError`で落とす。
    # ComfyUIから届く名前は実行時の文字列なので、型だけには頼らない。
    return request_translation(text, CONTEXTS[context])
