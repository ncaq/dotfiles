"""ComfyUIがアイドルになったらメモリを解放させる常駐プロセス。

ComfyUIはsmart memoryで実行後も重みをVRAMへ保持し続ける。
同じモデルを連続で使う分には正しい挙動だが、
使い終わって放置している間も抱えたままになる。
bulletではOllamaが同じGPUを使うので、
抱えられたままだと汎用モデルがCUDAのOOMで載らない。

ComfyUI本体にこれを時間で解く仕組みは無い。
0.33.1の`comfy/cli_args.py`には該当する引数が無く、
`--disable-smart-memory`は実行のたびに降ろす別物である。
上流でも「作業セッションの後にVRAMが解放されない」という要望が挙がったまま実装されていない。
https://github.com/Comfy-Org/ComfyUI/issues/3192

コンテナごと止めれば全て解決するが、それはできない。
ComfyUIはSQLiteへ保存した状態の一部をローカル版では復元できず、
アイドルだからと落とすと利用者が困る。
そのため`lib/container-socket-activation.nix`はアイドル停止を持たない。
プロセスは生かしたまま、メモリだけを返させる。

# アイドルの測り方

`/prompt`の`queue_remaining`が0でないなら、実行中か待機中のものがあるので動いている。

0の時に「いつから空か」を自分の観測だけで決めてはいけない。
確認は数分おきなので、その隙間に始まって終わった生成を丸ごと見落とす。
生成の直後に「ずっと空だった」と誤って判断して降ろすのが、一番やってはいけない挙動である。

代わりにComfyUI自身が記録した時刻を読む。
`execution_start`と`execution_success`には`add_message`がミリ秒の実時刻を打っていて、
`/history`の各件の`status.messages`から取れる。
これを使えば確認の間隔と無関係に最後の活動が分かる。

# 何を解放するか

`/free`へ`unload_models`と`free_memory`を立てて投げる。
前者がVRAMの重みを降ろし、後者が実行結果のキャッシュを捨ててRAMを返す。
`main.py`の`prompt_worker`はキューが空でもフラグを読みに行くので、
何も実行していない待機中でもこの要求は効く。
降ろした後の`gc.collect`と`soft_empty_cache`も本体がやる。

ただしRSSが起動直後の水準まで戻ることは期待できない。
Pythonのアロケータが確保済みの領域をOSへ返しきるとは限らないためである。
完全に返すにはプロセスの終了が要るが、それは上に書いた理由で採らない。

# 接続先の組み立て

環境変数から受け取るのはホストとポートだけにして、
`http://`はこのファイルの中で固定する。

完全なURLを渡してもらう方が`idle-free-memory.nix`の側は素直になるが、
そうすると`urlopen`へ渡るのが変数になり、
`file:`や独自スキームも開ける形だとしてruffがS310で警告する。
スキームが1つに定まっていることをソースの上で示せるなら、
抑制のコメントを置くよりそちらの方が正しい。
リテラルで始まるf-stringをその場で渡せば、ruffは警告しない。

# なぜ常駐するか

タイマーで起こす形だと、
最後に動いていた時刻をプロセスの外、
つまり`/run`のファイルへ置き直す必要がある。
起動しっぱなしなら変数で済む。
インタプリタの起動を数分おきに繰り返さずに済むという利点もある。
"""

import json
import os
import sys
import time
import urllib.request
from typing import cast

# HTTPの待ち時間の上限。
# 相手は同じコンテナの中のlocalhostなので、
# 返らないのは相手が詰まっているか落ちている時だけである。
# 短く切っても得るものは無いが、
# 無指定だとsocketの既定でぶら下がり続けるので上限自体は置く。
REQUEST_TIMEOUT_SECONDS = 30

# 解放を指示する本文。
# `main.py`は`flags.get("unload_models", free_memory)`の形で、
# `free_memory`を`unload_models`の既定値として読む。
# つまり`free_memory`だけでも同じ結果になるが、
# どちらを意図したのかが読めなくなるので両方書く。
FREE_PAYLOAD = {"unload_models": True, "free_memory": True}


def log(message: str) -> None:
    """journalへ残す。

    systemdはstderrをそのままjournaldへ流すので、
    ロギングの設定を持たずに`journalctl -M comfyui -u`で読める。
    バッファに溜めたまま次の確認まで出てこないと追いにくいので毎回流す。
    """
    print(f"[idle-free-memory] {message}", file=sys.stderr, flush=True)


def get_json(authority: str, path: str) -> object:
    """GETしてJSONを読む。

    ComfyUIのAPIには型が無いので`object`のまま返して、
    必要な形かどうかは呼び出し側で確かめる。

    組み立て済みのURLを受け取らずにここで繋ぐ理由はモジュールの冒頭にある。
    """
    with urllib.request.urlopen(
        f"http://{authority}{path}", timeout=REQUEST_TIMEOUT_SECONDS
    ) as response:
        body: bytes = response.read()
    parsed: object = json.loads(body)
    return parsed


def post_json(authority: str, path: str, payload: dict[str, bool]) -> None:
    """JSONをPOSTする。

    `Request`を変数へ置かずにその場で組むのも`get_json`と同じ理由による。
    """
    with urllib.request.urlopen(
        urllib.request.Request(
            f"http://{authority}{path}",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        ),
        timeout=REQUEST_TIMEOUT_SECONDS,
    ) as response:
        # 本文は空なので捨てる。
        # それでも読むのは、応答を受け取りきってから接続を閉じるためである。
        response.read()


def queue_remaining(authority: str) -> int:
    """キューに残っている数を返す。

    実行中のものも含まれるので、0でなければ何かしら動いている。
    """
    parsed = get_json(authority, "/prompt")
    if not isinstance(parsed, dict):
        raise ValueError("/promptがオブジェクトを返しませんでした")
    # `isinstance`だけでは要素の型が不明なままなので、
    # JSONのオブジェクトとして値を`object`へ寄せる。
    exec_info = cast(dict[str, object], parsed).get("exec_info")
    if not isinstance(exec_info, dict):
        raise ValueError("/promptの応答にexec_infoがありませんでした")
    remaining = cast(dict[str, object], exec_info).get("queue_remaining")
    if not isinstance(remaining, int):
        raise ValueError("/promptのqueue_remainingが整数ではありませんでした")
    return remaining


def _message_timestamps(entry: object) -> list[int]:
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
        timestamp = cast(dict[str, object], data).get("timestamp")
        if isinstance(timestamp, int):
            timestamps.append(timestamp)
    return timestamps


def latest_activity(authority: str) -> float | None:
    """ComfyUIが記録した最後の実行時刻をUNIX時刻の秒で返す。

    一度も実行していない場合はNoneを返す。

    `max_items=1`は`offset`の既定値の-1と組み合わさって、
    `len(history) - max_items`がoffsetになるため新しい方の1件を返す。
    """
    parsed = get_json(authority, "/history?max_items=1")
    if not isinstance(parsed, dict):
        raise ValueError("/historyがオブジェクトを返しませんでした")
    timestamps = [
        timestamp
        for entry in cast(dict[str, object], parsed).values()
        for timestamp in _message_timestamps(entry)
    ]
    if not timestamps:
        return None
    return max(timestamps) / 1000


def main() -> None:
    # 受け取るのはホストとポートだけで、スキームはこのファイルが決める。
    authority = os.environ["COMFYUI_AUTHORITY"]
    interval_seconds = float(os.environ["POLL_INTERVAL_SECONDS"])
    idle_seconds = float(os.environ["IDLE_SECONDS"])

    # 最後に動いていた時刻。
    # ComfyUIが記録する時刻と比べるので実時刻で持つ。
    last_activity = time.time()
    # 解放済みかどうか。
    # 解放してから次の活動があるまでの間、同じ要求を投げ続けないために持つ。
    #
    # 起動直後は未解放から始める。
    # 通常はコンテナが起きた直後で何も載っていないので、
    # 最初の1回だけ何も降ろさない要求が飛ぶことになるが、
    # 載っていなければ`unload_all_models`は何もしないので害は無い。
    # そのかわり、このプロセスだけが再起動した場合に、
    # 載ったままのモデルを取りこぼさずに済む。
    freed = False

    log(
        f"{interval_seconds:.0f}秒ごとに確認し、{idle_seconds:.0f}秒のアイドルで解放します"
    )

    while True:
        # 確認より先に待つ。
        # ComfyUIの起動を待つ経路をここに書かずに済む。
        time.sleep(interval_seconds)
        try:
            busy = 0 < queue_remaining(authority)
            latest = latest_activity(authority)
        except (OSError, ValueError) as error:
            # ComfyUIの再起動中や、モデルの読み込みで応答が詰まっている間は届かない。
            # 次の周回で回復するので、記録だけ残して続ける。
            # `urllib`の投げる`URLError`はOSErrorの、
            # `json`の投げる`JSONDecodeError`はValueErrorの下位にある。
            log(f"状態を取得できませんでした: {error}")
            continue
        now = time.time()
        if busy:
            last_activity = now
            freed = False
            continue
        if latest is not None and last_activity < latest:
            # 確認と確認の間に終わった生成をここで拾う。
            last_activity = latest
            freed = False
        if freed:
            continue
        if now - last_activity < idle_seconds:
            continue
        try:
            post_json(authority, "/free", FREE_PAYLOAD)
        except OSError as error:
            log(f"メモリの解放を要求できませんでした: {error}")
            continue
        freed = True
        log("アイドルが続いているのでメモリの解放を要求しました")


if __name__ == "__main__":
    main()
