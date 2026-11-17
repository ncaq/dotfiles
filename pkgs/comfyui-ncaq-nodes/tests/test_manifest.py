"""進捗の記録の読み書きの単体テスト。

読めない記録をどう扱うかは実際の中断ジョブでしか通らない経路で、
壊れると「再開したつもりが生成条件の照合を飛ばす」、
「完了しているのに記録の上では未完了に見える」といった、
気付きにくい失敗になる。
ファイルとJSONだけで完結しているのでここで固定する。
"""

import json
from pathlib import Path

import pytest
from manifest import Manifest, TranslatedSegment, read_manifest, write_manifest

segments: list[TranslatedSegment] = [
    {"scene": 0, "prompt": "歩く", "english": "walking"}
]


def write_json(path: Path, value: object) -> Path:
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    return path


def test_reads_written_manifest(tmp_path: Path) -> None:
    """書いた記録をそのまま読み戻せる。"""
    path = tmp_path / "manifest.json"
    write_manifest(
        path,
        Manifest(
            identity={"seed": 1},
            segments=segments,
            status="completed",
            completed_keyframes=2,
            completed_segments=3,
            video="out.webm",
        ),
    )
    loaded = read_manifest(path)
    assert loaded is not None
    assert loaded.identity == {"seed": 1}
    assert loaded.segments == segments
    # 件数は人が経過を見るためだけの値だが、
    # 既定値へ戻すと再開後の書き込みでnullへ潰れて、
    # 完了しているのに未完了に見える。
    assert loaded.completed_keyframes == 2
    assert loaded.completed_segments == 3
    # 再開すれば必ず書き直される項目は既定値へ戻す。
    assert loaded.status == "running"
    assert loaded.video is None
    assert loaded.error is None


def test_writes_without_copying(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """書き出しで`identity`と`segments`を複製しない。

    `dataclasses.asdict`はdictやlistのフィールドを辿って作り直すため、
    書き込みのたびにこの2つが丸ごと複製される。
    書き込みは区間ごとに起きるので、区間の数に対して二乗の複製になる。
    JSONへ渡ったものが同じオブジェクトのままかどうかで複製の有無を見る。
    """
    dumped: list[dict[str, object]] = []

    def dumps(value: dict[str, object], **_kwargs: object) -> str:
        dumped.append(value)
        return "{}"

    monkeypatch.setattr(json, "dumps", dumps)
    manifest = Manifest(identity={"seed": 1}, segments=segments)
    write_manifest(tmp_path / "manifest.json", manifest)
    assert [value["segments"] for value in dumped] == [manifest.segments]
    assert dumped[0]["segments"] is manifest.segments
    assert dumped[0]["identity"] is manifest.identity


def test_rejects_missing_file(tmp_path: Path) -> None:
    """ファイルが読めなければNoneを返す。"""
    assert read_manifest(tmp_path / "absent.json") is None


def test_rejects_invalid_encoding(tmp_path: Path) -> None:
    """UTF-8として読めないファイルはNoneを返す。"""
    path = tmp_path / "manifest.json"
    path.write_bytes(b"\xff\xfe")
    assert read_manifest(path) is None


@pytest.mark.parametrize(
    "raw",
    [
        "{",
        # JSONとしては妥当でもオブジェクトでなければ記録として読めない。
        "[]",
    ],
)
def test_rejects_invalid_json(tmp_path: Path, raw: str) -> None:
    """JSONのオブジェクトとして読めなければNoneを返す。"""
    path = tmp_path / "manifest.json"
    path.write_text(raw, encoding="utf-8")
    assert read_manifest(path) is None


@pytest.mark.parametrize(
    "fields",
    [
        {"segments": segments},
        {"identity": {"seed": 1}},
        {"identity": [], "segments": segments},
        {"identity": {"seed": 1}, "segments": {}},
    ],
)
def test_rejects_missing_identity_or_segments(
    tmp_path: Path, fields: dict[str, object]
) -> None:
    """再開の判定に使う2つが読めなければNoneを返す。"""
    path = write_json(tmp_path / "manifest.json", fields)
    assert read_manifest(path) is None


@pytest.mark.parametrize("count", [True, "2", 2.0, None])
def test_drops_invalid_count(tmp_path: Path, count: object) -> None:
    """件数として読めない値はNoneにするが、記録全体は捨てない。

    `bool`は`int`の派生なので、JSONの`true`が件数として通り得る。
    """
    path = write_json(
        tmp_path / "manifest.json",
        {
            "identity": {"seed": 1},
            "segments": segments,
            "completed_keyframes": count,
        },
    )
    loaded = read_manifest(path)
    assert loaded is not None
    assert loaded.completed_keyframes is None
