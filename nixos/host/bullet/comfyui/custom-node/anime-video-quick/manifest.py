# job IDごとの進捗の記録を読み書きするモジュール。
#
# ノード本体から分けているのはテストのため。
# `__init__.py`はComfyUI本体とtorchとPyAVをimportするので、
# 読み込むだけでGPUを持つ実行環境が要る。
# 記録の読み書きはファイルとJSONだけで完結していて、
# 壊れた記録を読んだ時の振る舞いこそ実際の中断ジョブでしか通らない経路なので、
# ここだけを素のPythonでテストできるようにする。
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, TypedDict, cast


class Segment(TypedDict):
    scene: int
    prompt: str


class TranslatedSegment(Segment):
    english: str


@dataclass
class Manifest:
    """job IDごとに出力ディレクトリへ置く進捗の記録。

    中断したジョブを同じjob IDで再開する時にどこまで終わっているかを見る。
    """

    # 生成条件。異なる条件で同じjob IDを使い回していないかの照合に使う。
    # キーを走査して比較するだけなので値の型は問わない。
    identity: dict[str, object]
    segments: list[TranslatedSegment]
    # ここから下は処理が進むにつれて埋まる。
    status: Literal["running", "completed", "failed"] = "running"
    completed_keyframes: int | None = None
    completed_segments: int | None = None
    video: str | None = None
    error: str | None = None


def optional_count(value: object) -> int | None:
    """進捗の件数として読み戻す。数として読めなければNoneにする。

    表示のためだけの値なので、
    壊れていても記録全体を捨てるほどのことではない。
    `bool`は`int`の派生なので、JSONの`true`が件数として通らないよう外す。
    """
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value


def read_manifest(path: Path) -> Manifest | None:
    """manifest.jsonを読む。期待する形をしていなければNoneを返す。

    旧スキーマや別プロセスが書いたファイルが置かれていることがあり、
    型注釈だけでは実行時の形を保証できない。
    JSONとして妥当とは限らないのと同じく、
    UTF-8として妥当とも読める状態とも限らないので、
    読み出しの失敗もまとめてNoneへ倒す。
    `UnicodeDecodeError`と`JSONDecodeError`はどちらも`ValueError`の派生で、
    権限や競合で読めない場合は`OSError`になる。

    再開の判定に使うのは`identity`と`segments`で、
    この2つが読めなければ記録として扱えないのでNoneを返す。
    `segments`は配列であることまでしか見ないので、
    要素が壊れていれば区間を生成する時に落ちる。

    進捗の件数は人が経過を見るためだけのものだが、
    既定値のまま置くと再開後の書き込みでnullへ潰れてしまう。
    その相が既に終わっていれば埋め直す書き込みも起きないので、
    完了しているのに記録の上では未完了に見える。
    数として読めた分はそのまま持ち越す。

    `status`と`video`と`error`は再開すれば必ず書き直されるので、
    既定値のまま置く。
    """
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(loaded, dict):
        return None
    fields = cast(dict[str, object], loaded)
    identity = fields.get("identity")
    segments = fields.get("segments")
    if not isinstance(identity, dict) or not isinstance(segments, list):
        return None
    return Manifest(
        identity=cast(dict[str, object], identity),
        segments=cast(list[TranslatedSegment], segments),
        completed_keyframes=optional_count(fields.get("completed_keyframes")),
        completed_segments=optional_count(fields.get("completed_segments")),
    )


def write_manifest(path: Path, manifest: Manifest) -> None:
    """進捗の記録を書き出す。

    `dataclasses.asdict`はdictやlistのフィールドを辿って作り直すため、
    `identity`と`segments`が書き込みのたびに丸ごと複製される。
    書き込みは区間ごとに起きるので、区間の数に対して二乗の複製になる。
    全フィールドがそのままJSONへ渡せる値なので、
    `vars`で属性の辞書を借りれば複製せずに同じJSONが得られる。
    """
    temporary = path.with_suffix(".partial.json")
    temporary.write_text(
        json.dumps(vars(manifest), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    os.replace(temporary, path)
