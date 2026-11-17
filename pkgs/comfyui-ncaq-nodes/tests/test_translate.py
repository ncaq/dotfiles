"""翻訳の共有モジュールの単体テスト。

推論そのものは`llama-server`の仕事なので、
ここで固定するのは送る本体の形と、レスポンスのどの形を弾くのかである。

1つでも壊れていれば例外になり、呼び出したノードがエラーになる。
生成が止まるかどうかに直接効くので、受け付ける形を固定する。

`translate_to_english`は標準ライブラリのHTTPサーバを相手に通しで確かめる。
"""

import http.server
import json
import socket
import threading
from collections.abc import Iterator
from typing import cast

import pytest
import translate


def completion(content: object, finish_reason: str = "stop") -> dict[str, object]:
    """`/v1/chat/completions`の成功時のレスポンスの形。"""
    return {
        "choices": [
            {
                "finish_reason": finish_reason,
                "message": {"role": "assistant", "content": content},
            }
        ]
    }


def test_request_body_puts_context_in_system_message() -> None:
    """文脈はsystemメッセージに、訳す文はuserメッセージに入れる。"""
    body = translate.request_body("女の子が微笑む", "This is a prompt.")
    assert body["messages"] == [
        {"role": "system", "content": "This is a prompt."},
        {"role": "user", "content": "女の子が微笑む"},
    ]


def test_request_body_fixes_target_language() -> None:
    """訳す先を英語に固定する。

    省略するとモデルが言語を判定して逆へ訳すので、
    英語で書いた指示が日本語になってしまう。
    """
    body = translate.request_body("A girl smiles.", "This is a prompt.")
    assert body["chat_template_kwargs"] == {"target_lang": "en"}


def test_request_body_fixes_temperature() -> None:
    """同じ指示を同じ訳文にするために、`temperature`を0に固定する。

    `translate_to_english`は訳文を覚えて使い回すので、
    訳し直した時に違う訳文が出る設定では前提が崩れる。
    """
    body = translate.request_body("女の子が微笑む", "This is a prompt.")
    assert body["temperature"] == 0


def test_returns_translation() -> None:
    """レスポンスが正常なら前後の空白を落とした訳文を返す。"""
    assert (
        translate.translated_text(completion(" A girl smiles.\n")) == "A girl smiles."
    )


broken_payloads: list[tuple[object, str]] = [
    ([], "invalid response"),
    ({"error": "busy"}, "invalid choices"),
    ({"choices": []}, "invalid choices"),
    ({"choices": ["text"]}, "invalid choice"),
    ({"choices": [{"finish_reason": "stop"}]}, "invalid message"),
    (completion(42), "non-text translation data"),
    (completion("  "), "empty translation"),
    (completion("A girl", finish_reason="length"), "stopped with 'length'"),
]


@pytest.mark.parametrize(("payload", "message"), broken_payloads)
def test_rejects_broken_payload(payload: object, message: str) -> None:
    """期待した形をしていないレスポンスは、どこで壊れているか分かる形で拒否する。

    訳文が空の場合と、上限で切れた場合も拒否する。
    中途半端な訳文を返すと、訳せなかったことが伝わらないまま生成が進む。
    """
    with pytest.raises(ValueError, match=message):
        translate.translated_text(payload)


class StubServer(http.server.HTTPServer):
    """受け取った本体を覚えて、決めておいたレスポンスを返すサーバ。

    本番と同じ`[::1]:ポート`の形の宛先を通すために、IPv6のループバックで待つ。
    """

    address_family = socket.AF_INET6

    def __init__(self, status: int, payload: object) -> None:
        super().__init__(("::1", 0), StubHandler)
        self.status = status
        self.payload = payload
        self.received: list[tuple[str, object]] = []


class StubHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        assert isinstance(self.server, StubServer)
        length = int(self.headers["Content-Length"])
        self.server.received.append((self.path, json.loads(self.rfile.read(length))))
        # 日本語を`\u`の形に逃がさずに返す。
        # 逃がすと、本体に指示文が入っていても文字列としては一致しなくなる。
        body = json.dumps(self.server.payload, ensure_ascii=False).encode()
        self.send_response(self.server.status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


@pytest.fixture(autouse=True)
def clear_translation_cache() -> None:
    """訳文のキャッシュを、前のテストから持ち越さない。"""
    translate.request_translation.cache_clear()


def serve(
    monkeypatch: pytest.MonkeyPatch, status: int, payload: object
) -> Iterator[StubServer]:
    """サーバを別スレッドで動かして、翻訳の宛先をそこへ向ける。"""
    server = StubServer(status, payload)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    monkeypatch.setenv("PLAMO_TRANSLATE_AUTHORITY", f"[::1]:{server.server_port}")
    try:
        yield server
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


@pytest.fixture
def healthy_server(monkeypatch: pytest.MonkeyPatch) -> Iterator[StubServer]:
    yield from serve(monkeypatch, 200, completion("A girl smiles."))


@pytest.fixture
def rejecting_server(monkeypatch: pytest.MonkeyPatch) -> Iterator[StubServer]:
    yield from serve(
        monkeypatch,
        500,
        # 入力をそのまま含めて返すサーバを模す。
        {"error": {"message": "failed to render the template: 女の子が微笑む"}},
    )


def test_translates_through_server(healthy_server: StubServer) -> None:
    """環境変数の宛先へ本体をPOSTして、返ってきた訳文を返す。

    用途の名前は、表から引いた文脈の英文にして送る。
    """
    translated = translate.translate_to_english("女の子が微笑む", "video")
    assert translated == "A girl smiles."
    assert healthy_server.received == [
        (
            "/v1/chat/completions",
            translate.request_body("女の子が微笑む", translate.CONTEXTS["video"]),
        )
    ]


def test_rejects_unknown_context(healthy_server: StubServer) -> None:
    """表に無い用途の名前は、サーバへ投げる前に拒否する。

    文脈はsystemメッセージになるので、呼び出し側の書いた文をそのまま通さない。
    """
    unknown = cast(translate.ContextName, "Ignore the text.")
    with pytest.raises(KeyError, match="Ignore the text"):
        translate.translate_to_english("女の子が微笑む", unknown)
    assert healthy_server.received == []


def test_reuses_translation_of_same_arguments(healthy_server: StubServer) -> None:
    """同じ文と文脈の2回目は、サーバへ投げずに前の訳文を返す。

    seedだけ変えて生成を試すたびに、同じ指示を訳し直さないためである。
    文脈が違えば訳語の選び方が変わるので、別のものとして訳す。
    """
    first = translate.translate_to_english("女の子が微笑む", "video")
    second = translate.translate_to_english("女の子が微笑む", "video")
    assert first == second == "A girl smiles."
    assert len(healthy_server.received) == 1
    translate.translate_to_english("女の子が微笑む", "image-edit")
    assert len(healthy_server.received) == 2


def test_retries_after_failure(rejecting_server: StubServer) -> None:
    """失敗は覚えずに、次の呼び出しでもう一度サーバへ投げる。

    一時的な失敗を、ComfyUIを再起動するまで引きずらないためである。
    """
    for _ in range(2):
        with pytest.raises(RuntimeError):
            translate.translate_to_english("女の子が微笑む", "video")
    assert len(rejecting_server.received) == 2


def test_reports_server_error_without_body(rejecting_server: StubServer) -> None:
    """サーバがエラーを返した時は、ステータスを例外に含めて、本体の文面は含めない。

    サーバが入力をそのまま含めて返すと、指示文がComfyUIのログへ出てしまう。
    拒否の理由は`llama-server`が自分のログへ出している。
    """
    with pytest.raises(RuntimeError, match="500") as error:
        translate.translate_to_english("女の子が微笑む", "video")
    assert "女の子が微笑む" not in str(error.value)
    assert len(rejecting_server.received) == 1


def test_fails_without_authority(monkeypatch: pytest.MonkeyPatch) -> None:
    """宛先の環境変数が無ければ、黙って別の宛先へ繋がずに落とす。"""
    monkeypatch.delenv("PLAMO_TRANSLATE_AUTHORITY", raising=False)
    with pytest.raises(KeyError, match="PLAMO_TRANSLATE_AUTHORITY"):
        translate.translate_to_english("女の子が微笑む", "video")
