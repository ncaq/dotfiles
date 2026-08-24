"""`state.py`の遷移のテスト。

実機で確かめられるのは1周回に1本の経路だけで、
しかも1周回は数分かかる。
順序と境界はここで固定する。
"""

from state import State, next_state

# しきい値。テストの中で意味を持つのは大小関係だけなので短くする。
IDLE = 600.0


def test_busy_resets_the_clock() -> None:
    # 実行中なら、履歴を見るまでもなく現在時刻が最後の活動になる。
    state, should_free = next_state(
        State(last_activity=0.0, freed=True),
        now=1000.0,
        busy=True,
        latest=None,
        idle_seconds=IDLE,
    )
    assert state == State(last_activity=1000.0, freed=False)
    assert should_free is False


def test_newer_history_is_picked_up() -> None:
    # 確認と確認の間に始まって終わった生成を拾い直す経路。
    # 拾ったら解放済みのフラグも戻す。
    state, should_free = next_state(
        State(last_activity=100.0, freed=True),
        now=1000.0,
        busy=False,
        latest=900.0,
        idle_seconds=IDLE,
    )
    assert state == State(last_activity=900.0, freed=False)
    assert should_free is False


def test_older_history_does_not_move_the_clock() -> None:
    state, should_free = next_state(
        State(last_activity=900.0, freed=True),
        now=2000.0,
        busy=False,
        latest=100.0,
        idle_seconds=IDLE,
    )
    assert state == State(last_activity=900.0, freed=True)
    assert should_free is False


def test_missing_history_does_not_move_the_clock() -> None:
    state, should_free = next_state(
        State(last_activity=900.0, freed=False),
        now=1000.0,
        busy=False,
        latest=None,
        idle_seconds=IDLE,
    )
    assert state == State(last_activity=900.0, freed=False)
    assert should_free is False


def test_already_freed_does_not_request_again() -> None:
    # しきい値を超え続けている間、同じ要求を投げ続けないことを固定する。
    state, should_free = next_state(
        State(last_activity=0.0, freed=True),
        now=10000.0,
        busy=False,
        latest=None,
        idle_seconds=IDLE,
    )
    assert state == State(last_activity=0.0, freed=True)
    assert should_free is False


def test_below_threshold_waits() -> None:
    state, should_free = next_state(
        State(last_activity=1000.0, freed=False),
        now=1000.0 + IDLE - 1,
        busy=False,
        latest=None,
        idle_seconds=IDLE,
    )
    assert state == State(last_activity=1000.0, freed=False)
    assert should_free is False


def test_at_threshold_frees() -> None:
    # ちょうど到達した周回で解放する。
    state, should_free = next_state(
        State(last_activity=1000.0, freed=False),
        now=1000.0 + IDLE,
        busy=False,
        latest=None,
        idle_seconds=IDLE,
    )
    assert state == State(last_activity=1000.0, freed=False)
    assert should_free is True


def test_freed_is_not_set_by_the_transition() -> None:
    # 解放が成功したかはHTTPの結果次第なので、ここでは立てない。
    # 立ててしまうと、要求に失敗した周回で次の活動まで再試行できなくなる。
    state, should_free = next_state(
        State(last_activity=1000.0, freed=False),
        now=10000.0,
        busy=False,
        latest=None,
        idle_seconds=IDLE,
    )
    assert should_free is True
    assert state.freed is False
