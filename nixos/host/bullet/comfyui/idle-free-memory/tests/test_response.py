"""`response.py`の解釈のテスト。

正常系より異常系が本体である。
ComfyUIのAPIには型が無く、
バージョンが上がって形が変わった時に、
例外ではなく静かに違う値が返ることを防ぐために書いている。
"""

import pytest
from response import latest_activity, message_timestamps, queue_remaining


def history(*timestamps: object) -> dict[str, object]:
    """`/history?max_items=1`の応答を、指定した時刻のメッセージ1件分で組み立てる。"""
    return {
        "8f0e": {
            "prompt": [],
            "outputs": {},
            "status": {
                "status_str": "success",
                "completed": True,
                "messages": [
                    ["execution_start", {"prompt_id": "8f0e", "timestamp": timestamp}]
                    for timestamp in timestamps
                ],
            },
        }
    }


def test_queue_remaining_reads_exec_info() -> None:
    assert queue_remaining({"exec_info": {"queue_remaining": 3}}) == 3


def test_queue_remaining_accepts_zero() -> None:
    assert queue_remaining({"exec_info": {"queue_remaining": 0}}) == 0


# 型を明示しないと、`{}`の要素の型が不明なまま`parametrize`へ渡ることになる。
BROKEN_QUEUE_RESPONSES: list[object] = [
    # オブジェクトですらない。
    [],
    # `exec_info`が無い。
    {},
    # `exec_info`がオブジェクトではない。
    {"exec_info": 1},
    # `queue_remaining`が無い。
    {"exec_info": {}},
    # `queue_remaining`が整数ではない。
    {"exec_info": {"queue_remaining": "3"}},
    {"exec_info": {"queue_remaining": None}},
    # `bool`は`int`の派生なので素の`isinstance`を通ってしまう。
    # 通すと`0 < True`が成立して常時busy扱いになり、解放が永久に止まる。
    {"exec_info": {"queue_remaining": True}},
    {"exec_info": {"queue_remaining": False}},
]


@pytest.mark.parametrize("parsed", BROKEN_QUEUE_RESPONSES)
def test_queue_remaining_rejects_broken_shape(parsed: object) -> None:
    with pytest.raises(ValueError):
        queue_remaining(parsed)


def test_message_timestamps_collects_every_message() -> None:
    entry = history(1000, 2000)["8f0e"]
    assert message_timestamps(entry) == [1000, 2000]


BROKEN_HISTORY_ENTRIES: list[object] = [
    # 件がオブジェクトではない。
    [],
    # `status`が無い。
    {},
    # `status`がオブジェクトではない。
    {"status": 1},
    # `messages`が無い。
    {"status": {}},
    # `messages`が配列ではない。
    {"status": {"messages": {}}},
    # 要素が配列ではない。
    {"status": {"messages": [1]}},
    # 要素が1つしかなくデータが無い。
    {"status": {"messages": [["execution_start"]]}},
    # データがオブジェクトではない。
    {"status": {"messages": [["execution_start", 1]]}},
    # `timestamp`が無い。
    {"status": {"messages": [["execution_start", {}]]}},
    # `timestamp`が整数ではない。
    {"status": {"messages": [["execution_start", {"timestamp": "1000"}]]}},
    # `bool`は`int`の派生なので素の`isinstance`を通ってしまう。
    # 通すと`True`が1ミリ秒の時刻として扱われる。
    {"status": {"messages": [["execution_start", {"timestamp": True}]]}},
]


@pytest.mark.parametrize("entry", BROKEN_HISTORY_ENTRIES)
def test_message_timestamps_skips_broken_shape(entry: object) -> None:
    assert message_timestamps(entry) == []


def test_latest_activity_takes_the_newest_in_seconds() -> None:
    assert latest_activity(history(1000, 3000, 2000)) == 3.0


def test_latest_activity_returns_none_for_empty_history() -> None:
    # 一度も実行していない状態は異常ではない。
    assert latest_activity({}) is None


def test_latest_activity_rejects_non_object() -> None:
    with pytest.raises(ValueError):
        latest_activity([])
