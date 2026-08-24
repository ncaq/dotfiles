"""アイドルかどうかの判定と、解放を要求するかどうかの決定。

時刻は引数で受け取り、
`time`にも`os.environ`にもHTTPにも触れない。
1周回分の遷移を1つの関数にまとめてあるので、
`main.py`のループを回さずに順序と境界をpytestで固定できる。

ここが一番壊れやすい。
「確認と確認の隙間に終わった生成を拾い直す」
「解放済みなら同じ要求を投げ直さない」
「しきい値を跨いだ最初の周回でだけ解放する」
の3つが同時に成り立っている必要があり、
どれか1つを崩しても実機では滅多に表面化しないためである。
"""

from dataclasses import dataclass


@dataclass(frozen=True)
class State:
    """周回をまたいで持ち越す状態。

    `last_activity`はComfyUIが最後に動いていた実時刻の秒。
    `freed`は解放を要求済みかどうかで、
    次の活動があるまで同じ要求を投げ続けないために持つ。
    """

    last_activity: float
    freed: bool


def next_state(
    state: State,
    now: float,
    busy: bool,
    latest: float | None,
    idle_seconds: float,
) -> tuple[State, bool]:
    """1周回分の遷移を行い、更新後の状態と解放を要求すべきかを返す。

    `busy`はキューに残りがあるかどうか、
    `latest`はComfyUI自身が記録した最後の活動時刻で、
    取れなかった場合はNoneを渡す。

    解放が成功したかどうかはHTTPの結果次第なので、
    ここでは`freed`を立てない。
    立てるのは実際に要求が通った後の呼び出し側である。
    要求に失敗した周回でフラグだけ進めてしまうと、
    次の活動があるまで再試行できなくなる。
    """
    if busy:
        return (State(last_activity=now, freed=False), False)
    if latest is not None and state.last_activity < latest:
        # 確認と確認の間に始まって終わった生成をここで拾う。
        state = State(last_activity=latest, freed=False)
    if state.freed:
        return (state, False)
    if now - state.last_activity < idle_seconds:
        return (state, False)
    return (state, True)
