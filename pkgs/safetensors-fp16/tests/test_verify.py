"""検証の単体テスト。

verifyが素通しするだけの飾りになっていないことを、
壊したファイルを拒否できるかで確かめる。
"""

from pathlib import Path

import numpy as np
import pytest
from conftest import load_safetensors, save_safetensors

from safetensors_fp16.convert import convert
from safetensors_fp16.verify import verify


def test_accepts_converted(src: Path, dst: Path) -> None:
    """正しく変換したものは通る。"""
    convert(str(src), str(dst), allow_overflow=False)
    verify(str(src), str(dst))


def test_rejects_modified_contents(src: Path, dst: Path) -> None:
    """1バイトでも書き換わっていれば気付く。

    ヘッダのサイズは変わらないので、
    中身まで突き合わせないと検出できない類の壊れ方である。
    """
    convert(str(src), str(dst), allow_overflow=False)
    with dst.open("r+b") as file:
        file.seek(dst.stat().st_size - 8)
        byte = file.read(1)
        file.seek(dst.stat().st_size - 8)
        file.write(bytes([byte[0] ^ 0xFF]))
    with pytest.raises(ValueError, match="contents differ"):
        verify(str(src), str(dst))


def test_rejects_shifted_contents(tmp_path: Path, dst: Path) -> None:
    """テンソルの並びがずれていれば気付く。

    合計サイズもテンソルの集合も一致するので、
    ヘッダの突き合わせだけでは通ってしまう。
    """
    src = tmp_path / "src.safetensors"
    first = np.array([1.0, 2.0, 3.0, 4.0], dtype="<f4")
    second = np.array([5.0, 6.0, 7.0, 8.0], dtype="<f4")
    save_safetensors(src, {"x.weight": first, "y.weight": second})
    save_safetensors(
        dst,
        {
            "x.weight": second.astype("<f2"),
            "y.weight": first.astype("<f2"),
        },
    )
    with pytest.raises(ValueError, match="contents differ"):
        verify(str(src), str(dst))


def test_rejects_missing_tensor(
    src: Path, dst: Path, tensors: dict[str, np.ndarray], metadata: dict[str, str]
) -> None:
    """テンソルが欠けていれば気付く。"""
    converted = {
        name: array.astype("<f2") if array.dtype == np.dtype("<f4") else array
        for name, array in tensors.items()
        if name != "b.bias"
    }
    save_safetensors(dst, converted, metadata)
    with pytest.raises(ValueError, match="tensor names differ"):
        verify(str(src), str(dst))


def test_rejects_unconverted_dtype(
    src: Path, dst: Path, tensors: dict[str, np.ndarray], metadata: dict[str, str]
) -> None:
    """F32のまま残っていれば気付く。"""
    save_safetensors(dst, tensors, metadata)
    with pytest.raises(ValueError, match="dtype F32 became F32"):
        verify(str(src), str(dst))


def test_rejects_different_metadata(src: Path, dst: Path) -> None:
    """__metadata__が落ちていれば気付く。"""
    convert(str(src), str(dst), allow_overflow=False)
    _, converted = load_safetensors(dst)
    save_safetensors(dst, converted)
    with pytest.raises(ValueError, match="__metadata__ differs"):
        verify(str(src), str(dst))
