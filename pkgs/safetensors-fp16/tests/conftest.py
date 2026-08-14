"""テスト用にsafetensorsを読み書きするヘルパー。

正しいファイルの読み書きはsafetensorsライブラリに任せる。
本体のformat.pyでテストデータを作ると、
読み書きが揃って同じ勘違いをしていても検出できない。
本家の実装をリファレンスに置けば、
本体が仕様から外れた時に食い違いとして現れる。

本体がライブラリを使わないのは、
Python APIが全テンソルの辞書をメモリに要求する設計で、
数十GBのファイルには使えないからである。
テストが扱うのは数百バイトなので、この制約は問題にならない。

壊れたファイルはライブラリでは作れないので、
そちらだけ生のバイト列から組み立てる。
"""

# safetensorsのスタブは`safe_open.metadata`に戻り値の注釈が無く、
# `save_file`と`load_file`もPathLikeとndarrayの型引数が埋まっていない。
# 上流に型が付くまではこのファイルでだけ落とす。
# 下の関数は戻り値の型を宣言してあるので、
# 不明な型がテスト本体へ漏れることはない。
# pyright: reportUnknownMemberType=none
# pyright: reportUnknownVariableType=none

import json
import struct
from pathlib import Path
from typing import cast

import numpy as np
import pytest
from safetensors import safe_open
from safetensors.numpy import load_file, save_file

# numpyのdtypeとsafetensorsのdtype名の対応。
# 壊れたファイルを組み立てる時にだけ使う。
DTYPE_NAME: dict[np.dtype, str] = {
    np.dtype("<f4"): "F32",
    np.dtype("<f2"): "F16",
    np.dtype("<i8"): "I64",
    np.dtype("uint8"): "U8",
}


def save_safetensors(
    path: Path,
    tensors: dict[str, np.ndarray],
    metadata: dict[str, str] | None = None,
) -> None:
    """テンソルをsafetensorsとして書き出す。"""
    save_file(tensors, str(path), metadata=metadata)


def load_safetensors(path: Path) -> tuple[dict[str, str], dict[str, np.ndarray]]:
    """safetensorsを読んで__metadata__とテンソルを返す。"""
    with safe_open(str(path), framework="numpy") as file:
        metadata: dict[str, str] | None = file.metadata()
    tensors: dict[str, np.ndarray] = load_file(str(path))
    return metadata or {}, tensors


def read_header(path: Path) -> dict[str, object]:
    """ヘッダのJSONをそのまま読み出す。

    `write_header`の対。
    ライブラリはヘッダを整理して返すので、
    キーの並びや`__metadata__`の有無といった、
    ファイル上の見た目そのものを見たい時に使う。
    """
    with path.open("rb") as file:
        (header_length,) = struct.unpack("<Q", file.read(8))
        parsed = json.loads(file.read(header_length))
    assert isinstance(parsed, dict)
    return cast(dict[str, object], parsed)


def write_header(path: Path, header: object, data: bytes = b"") -> None:
    """任意のJSONをヘッダとして持つファイルを書く。

    ライブラリが作れない壊れ方を再現するためのもの。
    ヘッダの妥当性は一切確かめない。
    """
    raw = json.dumps(header, separators=(",", ":")).encode("utf-8")
    raw += b" " * (-(8 + len(raw)) % 8)
    with path.open("wb") as file:
        file.write(struct.pack("<Q", len(raw)))
        file.write(raw)
        file.write(data)


def save_raw_safetensors(
    path: Path,
    tensors: dict[str, np.ndarray],
    dtype_names: dict[str, str] | None = None,
) -> None:
    """テンソルからヘッダを組み立てて書き出す。

    dtype_namesでヘッダのdtype名だけを差し替えられる。
    実際のデータと食い違うdtypeを載せた壊れたファイルを作るために使う。
    """
    header: dict[str, object] = {}
    offset = 0
    for name, array in tensors.items():
        size = array.nbytes
        header[name] = {
            "dtype": (dtype_names or {}).get(name, DTYPE_NAME[array.dtype]),
            "shape": list(array.shape),
            "data_offsets": [offset, offset + size],
        }
        offset += size
    write_header(path, header, b"".join(array.tobytes() for array in tensors.values()))


@pytest.fixture
def tensors() -> dict[str, np.ndarray]:
    """変換で起きうる場合を一通り含んだテンソル。

    F32とそれ以外の混在、空テンソル、スカラー、
    fp16への丸めの境界値を入れてある。
    """
    rng = np.random.default_rng(0)
    return {
        "a.weight": (rng.standard_normal((64, 128)) * 3).astype("<f2"),
        "b.weight": (rng.standard_normal((128, 256)) * 3).astype("<f4"),
        "b.bias": np.array([1.5, -2.25, 3.125], dtype="<f4"),
        "c.scalar": np.array(0.5, dtype="<f4"),
        "d.empty": np.zeros((0, 8), dtype="<f4"),
        "e.index": np.arange(16, dtype="<i8"),
        "f.raw": rng.integers(0, 256, 32, dtype=np.uint8),
        # 仮数の最下位が偶数へ丸められる境界と、fp16のsubnormalの下限付近。
        "g.edge": np.array(
            [2049.0, 2051.0, -2049.0, 6e-08, 1e-08, 0.0, -0.0], dtype="<f4"
        ),
    }


@pytest.fixture
def metadata() -> dict[str, str]:
    return {"format": "pt", "note": "fixture"}


@pytest.fixture
def src(
    tmp_path: Path, tensors: dict[str, np.ndarray], metadata: dict[str, str]
) -> Path:
    """変換元のsafetensors。"""
    path = tmp_path / "src.safetensors"
    save_safetensors(path, tensors, metadata)
    return path


@pytest.fixture
def dst(tmp_path: Path) -> Path:
    """変換先のパス。まだファイルは無い。"""
    return tmp_path / "dst.safetensors"
