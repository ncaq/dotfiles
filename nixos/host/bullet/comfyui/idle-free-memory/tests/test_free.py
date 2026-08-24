"""`main.py`の`free_if_needed`のテスト。

`state.py`のdocstringは「`freed`を立てるのは要求が通った後の呼び出し側である」と書き、
`test_freed_is_not_set_by_the_transition`が遷移の側を固定している。
その対になる呼び出し側がここである。

片側だけを固定していると、
要求を`try`の外へ出しても、
`except`節で状態を進めてしまっても、テストは緑のまま通る。
実機では解放が次の活動まで再試行されなくなるだけなので気付けない。
"""

import http.client

import pytest
from main import free_if_needed
from state import State

IDLE_STATE = State(last_activity=1000.0, freed=False)


def test_does_nothing_when_not_requested() -> None:
    calls: list[int] = []

    def request_free() -> None:
        calls.append(1)

    assert free_if_needed(IDLE_STATE, should_free=False, request_free=request_free) == (
        IDLE_STATE
    )
    assert calls == []


def test_marks_freed_after_a_successful_request() -> None:
    calls: list[int] = []

    def request_free() -> None:
        calls.append(1)

    state = free_if_needed(IDLE_STATE, should_free=True, request_free=request_free)
    assert calls == [1]
    assert state == State(last_activity=1000.0, freed=True)


@pytest.mark.parametrize(
    "error",
    [
        OSError("接続できませんでした"),
        http.client.RemoteDisconnected("切断されました"),
    ],
)
def test_keeps_freed_false_when_the_request_fails(error: Exception) -> None:
    # 失敗した周回でフラグだけ進めると、次の活動まで再試行できなくなる。
    def request_free() -> None:
        raise error

    state = free_if_needed(IDLE_STATE, should_free=True, request_free=request_free)
    assert state == IDLE_STATE


def test_does_not_swallow_unexpected_errors() -> None:
    # HTTPの失敗だけを吸収する。
    # それ以外はこちらの不具合なので、握り潰さずにユニットごと落とす。
    def request_free() -> None:
        raise ValueError("想定していない失敗")

    with pytest.raises(ValueError):
        free_if_needed(IDLE_STATE, should_free=True, request_free=request_free)
