"""翻訳の共有モジュールの単体テスト。

ネットワークを叩くのは`session.get`だけで、
レスポンスの解釈は入れ子の配列を辿るだけの純粋な処理である。

壊れたレスポンスの扱いはノードの統合で変わっている。
以前のanime-video-quickは壊れた区間を黙って読み飛ばして残りを繋げていたが、
今は1つでも壊れていれば`ValueError`になり、
呼び出し側が訳文全体を捨てて日本語の原文をそのままプロンプトにする。
生成結果に直接効くので、どの形を弾くのかをここで固定する。
"""

from typing import Any

import pytest
import translate


def test_joins_segments() -> None:
    """入れ子の配列から訳文を順に繋げる。"""
    payload = [[["Hello", "こんにちは"], [" world", " 世界"]], None, "ja"]
    assert translate.translated_text(payload) == "Hello world"


broken_payloads: list[tuple[object, str]] = [
    ({"translation": "Hello"}, "invalid response"),
    ([], "invalid response"),
    ([[]], "invalid segments"),
    ([[[]]], "invalid segment"),
    ([[[42]]], "non-text translation data"),
]


@pytest.mark.parametrize(("payload", "message"), broken_payloads)
def test_rejects_broken_payload(payload: object, message: str) -> None:
    """期待した形をしていないレスポンスは、どこで壊れているか分かる形で拒否する。"""
    with pytest.raises(ValueError, match=message):
        translate.translated_text(payload)


class StubResponse:
    """`session.get`の戻り値の代わり。"""

    def __init__(self, payload: object) -> None:
        self.payload = payload

    def raise_for_status(self) -> None:
        pass

    def json(self) -> object:
        return self.payload


def test_rejects_empty_translation(monkeypatch: pytest.MonkeyPatch) -> None:
    """訳文が空文字列であれば拒否する。

    原文へ倒すのは呼び出し側の判断なので、
    ここで空文字列を返すと訳せなかったことが伝わらない。
    """

    def get(*_args: object, **_kwargs: object) -> Any:
        return StubResponse([[["", "こんにちは"]]])

    monkeypatch.setattr(translate.session, "get", get)
    with pytest.raises(ValueError, match="empty translation"):
        translate.translate_to_english("こんにちは")


def test_returns_translation(monkeypatch: pytest.MonkeyPatch) -> None:
    """レスポンスが正常なら訳文を返す。"""

    def get(*_args: object, **_kwargs: object) -> Any:
        return StubResponse([[["Hello", "こんにちは"]]])

    monkeypatch.setattr(translate.session, "get", get)
    assert translate.translate_to_english("こんにちは") == "Hello"
