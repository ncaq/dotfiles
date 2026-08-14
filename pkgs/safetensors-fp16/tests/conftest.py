"""テスト用にsafetensorsを読み書きするヘルパー。

本体のformat.pyとは独立に実装する。
本体の関数でテストデータを作ると、
読み書きが揃って同じ勘違いをしていても検出できないからである。
"""

import json
import struct
from pathlib import Path

import numpy as np
import pytest

# numpyのdtypeとsafetensorsのdtype名の対応。テストで使う分だけ。
DTYPE_NAME: dict[np.dtype, str] = {
    np.dtype("<f4"): "F32",
    np.dtype("<f2"): "F16",
    np.dtype("<i8"): "I64",
    np.dtype("uint8"): "U8",
}
NAME_DTYPE: dict[str, np.dtype] = {name: dtype for dtype, name in DTYPE_NAME.items()}


def save_safetensors(
    path: Path,
    tensors: dict[str, np.ndarray],
    metadata: dict[str, str] | None = None,
    dtype_names: dict[str, str] | None = None,
) -> None:
    """テンソルをsafetensorsとして書き出す。

    dtype_namesを渡すとヘッダのdtype名だけを差し替えられる。
    未知のdtypeを載せた壊れたファイルを作るために使う。
    """
    header: dict[str, object] = {}
    if metadata is not None:
        header["__metadata__"] = metadata
    offset = 0
    for name, array in tensors.items():
        size = array.nbytes
        header[name] = {
            "dtype": (dtype_names or {}).get(name, DTYPE_NAME[array.dtype]),
            "shape": list(array.shape),
            "data_offsets": [offset, offset + size],
        }
        offset += size
    raw = json.dumps(header, separators=(",", ":")).encode("utf-8")
    raw += b" " * (-(8 + len(raw)) % 8)
    with path.open("wb") as file:
        file.write(struct.pack("<Q", len(raw)))
        file.write(raw)
        for array in tensors.values():
            file.write(array.tobytes())


def load_safetensors(path: Path) -> tuple[dict[str, object], dict[str, np.ndarray]]:
    """safetensorsを読んでヘッダとテンソルを返す。"""
    with path.open("rb") as file:
        (header_length,) = struct.unpack("<Q", file.read(8))
        header = json.loads(file.read(header_length))
        data = file.read()
    tensors: dict[str, np.ndarray] = {}
    for name, info in header.items():
        if name == "__metadata__":
            continue
        begin, end = info["data_offsets"]
        array = np.frombuffer(data[begin:end], dtype=NAME_DTYPE[info["dtype"]])
        tensors[name] = array.reshape(info["shape"])
    return header, tensors


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
