"""ComfyUIの応答を解釈する。

HTTPには触れず、
`json.loads`が返したものを受け取って必要な値だけを取り出す。
ComfyUIのAPIには型が無いので、
引数は`object`で受けて形をその場で確かめる。

`main.py`から分けてあるのは、
ここがComfyUIのバージョンが上がると壊れる側だからである。
しかも壊れ方は「例外が出る」ではなく、
「形が変わって静かに違う値を返す」になりやすい。
`while True`も`time.sleep`も`os.environ`も持たない形にしておけば、
壊れた入力を並べたpytestで分岐を固定できる。
"""

from typing import cast


def _as_int(value: object) -> int | None:
    """JSONの整数として読める場合だけ返す。

    `isinstance(value, int)`だけでは`bool`も通る。
    `bool`が`int`の派生だからである。
    この関数群の存在意義は壊れた形を弾くことなので、
    `true`が0や1として流れ込む経路を先に塞ぐ。
    """
    if isinstance(value, bool):
        return None
    if not isinstance(value, int):
        return None
    return value


def queue_remaining(parsed: object) -> int:
    """`/prompt`の応答からキューに残っている数を取り出す。

    実行中のものも含まれるので、0でなければ何かしら動いている。

    形が合わない場合はValueErrorを投げる。
    応答がオブジェクトでない、
    `exec_info`が無いかオブジェクトでない、
    `queue_remaining`が数値でない、の3経路がある。
    呼び出し側はこれを捕まえてその周回を飛ばす。
    """
    if not isinstance(parsed, dict):
        raise ValueError("/promptがオブジェクトを返しませんでした")
    # `isinstance`だけでは要素の型が不明なままなので、
    # JSONのオブジェクトとして値を`object`へ寄せる。
    exec_info = cast(dict[str, object], parsed).get("exec_info")
    if not isinstance(exec_info, dict):
        raise ValueError("/promptの応答にexec_infoがありませんでした")
    remaining = _as_int(cast(dict[str, object], exec_info).get("queue_remaining"))
    if remaining is None:
        raise ValueError("/promptのqueue_remainingが整数ではありませんでした")
    return remaining


def message_timestamps(entry: object) -> list[int]:
    """履歴1件が持つ状態メッセージの時刻をミリ秒で集める。

    要素は`("execution_start", {...})`のタプルがJSONの配列になったものである。
    形が違うものは黙って飛ばす。
    ここで欲しいのは最後の活動時刻だけで、
    1件読めなくても他の件と次の周回で足りるためである。
    """
    if not isinstance(entry, dict):
        return []
    status = cast(dict[str, object], entry).get("status")
    if not isinstance(status, dict):
        return []
    messages = cast(dict[str, object], status).get("messages")
    if not isinstance(messages, list):
        return []
    timestamps: list[int] = []
    for message in cast(list[object], messages):
        if not isinstance(message, list):
            continue
        pair = cast(list[object], message)
        if len(pair) < 2:
            continue
        data = pair[1]
        if not isinstance(data, dict):
            continue
        timestamp = _as_int(cast(dict[str, object], data).get("timestamp"))
        if timestamp is not None:
            timestamps.append(timestamp)
    return timestamps


def latest_activity(parsed: object) -> float | None:
    """`/history`の応答から最後の実行時刻をUNIX時刻の秒で取り出す。

    一度も実行していない場合はNoneを返す。

    件はあるのに時刻が1つも取れなかった場合はValueErrorを投げる。
    `message_timestamps`は形の合わないものを黙って飛ばすので、
    ComfyUIが`status.messages`の形やキー名を変えると全件が飛ばされる。
    ここでNoneを返すと呼び出し側は「一度も実行していない」とみなし、
    自分の観測だけでアイドルを判定する状態へ静かに退行する。
    それはこのプロセスが避けようとしている、
    生成の直後に降ろす動作そのものである。
    件が0件の場合と区別して、上流の変化に気付けるようにする。

    `/history?max_items=1`は`offset`の既定値の-1と組み合わさって、
    `len(history) - max_items`がoffsetになるため新しい方の1件を返す。
    """
    if not isinstance(parsed, dict):
        raise ValueError("/historyがオブジェクトを返しませんでした")
    entries = cast(dict[str, object], parsed)
    timestamps = [
        timestamp
        for entry in entries.values()
        for timestamp in message_timestamps(entry)
    ]
    if timestamps:
        return max(timestamps) / 1000
    if entries:
        raise ValueError(f"/historyの{len(entries)}件から時刻を1つも取れませんでした")
    return None
