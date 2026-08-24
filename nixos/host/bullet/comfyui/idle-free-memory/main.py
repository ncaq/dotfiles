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

# なぜファイルを分けるか

このファイルはHTTPと環境変数とループだけを持ち、
応答の解釈は`response.py`へ、
アイドルの判定は`state.py`へ置いてある。
どちらもpytestで固定したい対象で、
`while True`と`time.sleep`と同居していると回さずに試せないためである。
"""

import json
import os
import sys
import time
import urllib.request

from response import latest_activity, queue_remaining
from state import State, next_state

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
    ロギングの設定を持たずに、
    `journalctl -M comfyui -u comfyui-idle-free-memory`でそのまま読める。
    バッファに溜めたまま次の確認まで出てこないと追いにくいので毎回流す。
    """
    print(f"[idle-free-memory] {message}", file=sys.stderr, flush=True)


def get_json(authority: str, path: str) -> object:
    """GETしてJSONを読む。

    ComfyUIのAPIには型が無いので`object`のまま返して、
    必要な形かどうかは`response.py`側で確かめる。

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


def main() -> None:
    # 受け取るのはホストとポートだけで、スキームはこのファイルが決める。
    authority = os.environ["COMFYUI_AUTHORITY"]
    interval_seconds = float(os.environ["POLL_INTERVAL_SECONDS"])
    idle_seconds = float(os.environ["IDLE_SECONDS"])

    # 起動直後は未解放から始める。
    # 通常はコンテナが起きた直後で何も載っていないので、
    # 最初の1回だけ何も降ろさない要求が飛ぶことになるが、
    # 載っていなければ`unload_all_models`は何もしないので害は無い。
    # そのかわり、このプロセスだけが再起動した場合に、
    # 載ったままのモデルを取りこぼさずに済む。
    state = State(last_activity=time.time(), freed=False)

    log(
        f"{interval_seconds:.0f}秒ごとに確認し、{idle_seconds:.0f}秒のアイドルで解放します"
    )

    while True:
        # 確認より先に待つ。
        # ComfyUIの起動を待つ経路をここに書かずに済む。
        time.sleep(interval_seconds)
        try:
            busy = 0 < queue_remaining(get_json(authority, "/prompt"))
            latest = latest_activity(get_json(authority, "/history?max_items=1"))
        except (OSError, ValueError) as error:
            # ComfyUIの再起動中や、モデルの読み込みで応答が詰まっている間は届かない。
            # 次の周回で回復するので、記録だけ残して続ける。
            # `urllib`の投げる`URLError`はOSErrorの、
            # `json`の投げる`JSONDecodeError`はValueErrorの下位にある。
            log(f"状態を取得できませんでした: {error}")
            continue
        state, should_free = next_state(
            state,
            now=time.time(),
            busy=busy,
            latest=latest,
            idle_seconds=idle_seconds,
        )
        if not should_free:
            continue
        try:
            post_json(authority, "/free", FREE_PAYLOAD)
        except OSError as error:
            log(f"メモリの解放を要求できませんでした: {error}")
            continue
        # 要求が通ってから解放済みにする。
        # `next_state`がここを立てないのは、
        # 失敗した周回でフラグだけ進めて再試行できなくならないようにするためである。
        state = State(last_activity=state.last_activity, freed=True)
        log("アイドルが続いているのでメモリの解放を要求しました")


if __name__ == "__main__":
    main()
