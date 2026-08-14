"""変換の単体テスト。"""

import struct
from pathlib import Path

import numpy as np
import pytest
from conftest import load_safetensors, save_safetensors

from safetensors_fp16.convert import convert


def test_converts_f32_to_f16(
    src: Path, dst: Path, tensors: dict[str, np.ndarray]
) -> None:
    """F32のテンソルがF16になり、値がnumpyのキャストと一致する。"""
    convert(str(src), str(dst), allow_overflow=False)
    _, converted = load_safetensors(dst)
    for name, array in tensors.items():
        if array.dtype != np.dtype("<f4"):
            continue
        assert converted[name].dtype == np.dtype("<f2"), name
        expected = array.astype("<f2")
        assert np.array_equal(expected.view("<u2"), converted[name].view("<u2")), name


def test_keeps_other_dtypes(
    src: Path, dst: Path, tensors: dict[str, np.ndarray]
) -> None:
    """F32以外のテンソルはdtypeも中身も変わらない。"""
    convert(str(src), str(dst), allow_overflow=False)
    _, converted = load_safetensors(dst)
    for name, array in tensors.items():
        if array.dtype == np.dtype("<f4"):
            continue
        assert converted[name].dtype == array.dtype, name
        assert np.array_equal(array.view("uint8"), converted[name].view("uint8")), name


def test_keeps_shapes(src: Path, dst: Path, tensors: dict[str, np.ndarray]) -> None:
    """shapeは空テンソルもスカラーも保たれる。"""
    convert(str(src), str(dst), allow_overflow=False)
    _, converted = load_safetensors(dst)
    assert {name: array.shape for name, array in converted.items()} == {
        name: array.shape for name, array in tensors.items()
    }


def test_keeps_metadata(src: Path, dst: Path, metadata: dict[str, str]) -> None:
    """__metadata__はそのまま引き継がれる。"""
    convert(str(src), str(dst), allow_overflow=False)
    header, _ = load_safetensors(dst)
    assert header["__metadata__"] == metadata


def test_rounds_to_nearest_even(src: Path, dst: Path) -> None:
    """丸めはround-to-nearest-evenで、subnormalも潰さない。"""
    convert(str(src), str(dst), allow_overflow=False)
    _, converted = load_safetensors(dst)
    assert [float(value) for value in converted["g.edge"]] == [
        # 2049と2051はどちらも中間値だが、仮数の最下位が偶数になる側へ丸める。
        2048.0,
        2052.0,
        -2048.0,
        # fp16のsubnormalとして表せる値は保たれ、表せない値は0になる。
        5.960464477539063e-08,
        0.0,
        0.0,
        -0.0,
    ]


def test_aligns_header(src: Path, dst: Path) -> None:
    """データ領域が8バイト境界から始まる。"""
    convert(str(src), str(dst), allow_overflow=False)
    with dst.open("rb") as file:
        (header_length,) = struct.unpack("<Q", file.read(8))
    assert (8 + header_length) % 8 == 0


def test_rejects_overflow(tmp_path: Path, dst: Path) -> None:
    """fp16の範囲を超える重みがあれば失敗する。"""
    src = tmp_path / "overflow.safetensors"
    save_safetensors(src, {"big.weight": np.array([70000.0, 1.0], dtype="<f4")})
    with pytest.raises(FloatingPointError):
        convert(str(src), str(dst), allow_overflow=False)


def test_allows_overflow_when_requested(tmp_path: Path, dst: Path) -> None:
    """明示的に許可すればinfへ潰して変換を続ける。"""
    src = tmp_path / "overflow.safetensors"
    save_safetensors(src, {"big.weight": np.array([70000.0, 1.0], dtype="<f4")})
    convert(str(src), str(dst), allow_overflow=True)
    _, converted = load_safetensors(dst)
    assert np.isinf(converted["big.weight"][0])


def test_rejects_unknown_dtype(tmp_path: Path, dst: Path) -> None:
    """知らないdtypeは黙って素通しせずエラーにする。"""
    src = tmp_path / "unknown.safetensors"
    save_safetensors(
        src,
        {"x.weight": np.zeros(4, dtype="<f4")},
        dtype_names={"x.weight": "F4_E2M1"},
    )
    with pytest.raises(ValueError, match="unknown dtype"):
        convert(str(src), str(dst), allow_overflow=False)


def test_rejects_inconsistent_offsets(tmp_path: Path, dst: Path) -> None:
    """shapeとdtypeから決まる長さに合わないヘッダは受け付けない。"""
    src = tmp_path / "broken.safetensors"
    save_safetensors(src, {"x.weight": np.zeros(4, dtype="<f4")})
    # F32の16バイトをF16と偽ると、必要な長さが8バイトになって食い違う。
    save_safetensors(
        src,
        {"x.weight": np.zeros(4, dtype="<f4")},
        dtype_names={"x.weight": "F16"},
    )
    with pytest.raises(ValueError, match="data_offsets span"):
        convert(str(src), str(dst), allow_overflow=False)
