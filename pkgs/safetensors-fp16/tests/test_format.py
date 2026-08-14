"""ヘッダの検証の単体テスト。

safetensorsのヘッダはJSONなので、
中身は何が入っていてもおかしくない。
数十GBの変換を始めてから壊れているのに気付くのは高くつくので、
入口で落ちること、
そして何が壊れているのか分かるメッセージが出ることを確かめる。

正しいファイルでは通れない経路なので、
ここだけはヘッダを生で組み立てる。
"""

from pathlib import Path

import numpy as np
import pytest
from conftest import save_raw_safetensors, write_header

from safetensors_fp16.convert import convert
from safetensors_fp16.format import parse_tensors, read_header


def test_rejects_short_file(tmp_path: Path) -> None:
    """ヘッダ長すら入っていないファイルを拒否する。"""
    path = tmp_path / "short.safetensors"
    path.write_bytes(b"abc")
    with path.open("rb") as file, pytest.raises(ValueError, match="too short"):
        read_header(file)


def test_rejects_truncated_header(tmp_path: Path) -> None:
    """ヘッダ長が実際の残りより大きいファイルを拒否する。"""
    path = tmp_path / "truncated.safetensors"
    path.write_bytes((1024).to_bytes(8, "little") + b"{}")
    with (
        path.open("rb") as file,
        pytest.raises(ValueError, match="header is truncated"),
    ):
        read_header(file)


def test_rejects_oversized_header(tmp_path: Path) -> None:
    """上限を超えるヘッダ長を、読み込む前に拒否する。

    u64をそのまま`read`へ渡すと巨大な確保が起きるので、
    切り詰めの判定へ到達する前に落とす必要がある。
    """
    path = tmp_path / "huge.safetensors"
    path.write_bytes((2**64 - 1).to_bytes(8, "little") + b"{}")
    with (
        path.open("rb") as file,
        pytest.raises(ValueError, match="at most 100000000 is accepted"),
    ):
        read_header(file)


def test_rejects_non_object_header(tmp_path: Path) -> None:
    """JSONではあるがオブジェクトでないヘッダを拒否する。"""
    path = tmp_path / "array.safetensors"
    write_header(path, [1, 2, 3])
    with (
        path.open("rb") as file,
        pytest.raises(ValueError, match="header is not a JSON object"),
    ):
        read_header(file)


def test_rejects_unaligned_header(tmp_path: Path) -> None:
    """データ領域が8バイト境界から始まらないファイルを拒否する。"""
    path = tmp_path / "unaligned.safetensors"
    # write_headerは境界へ揃えてしまうので、ここだけ自分で組み立てる。
    raw = b'{"a":1}'
    path.write_bytes(len(raw).to_bytes(8, "little") + raw)
    with path.open("rb") as file, pytest.raises(ValueError, match="byte boundary"):
        read_header(file)


def test_rejects_non_object_metadata() -> None:
    """__metadata__がオブジェクトでなければ拒否する。"""
    with pytest.raises(ValueError, match="__metadata__ is not a JSON object"):
        parse_tensors({"__metadata__": "text"}, 0)


def test_rejects_non_object_entry() -> None:
    """テンソルの記述がオブジェクトでなければ拒否する。"""
    with pytest.raises(ValueError, match="entry is not a JSON object"):
        parse_tensors({"x.weight": "text"}, 0)


def test_rejects_non_string_dtype() -> None:
    """dtypeが文字列でなければ拒否する。"""
    entry = {"dtype": 32, "shape": [1], "data_offsets": [0, 4]}
    with pytest.raises(ValueError, match="unknown dtype"):
        parse_tensors({"x.weight": entry}, 4)


def test_rejects_non_array_shape() -> None:
    """shapeが配列でなければ拒否する。"""
    entry = {"dtype": "F32", "shape": 4, "data_offsets": [0, 4]}
    with pytest.raises(ValueError, match="shape is not an array"):
        parse_tensors({"x.weight": entry}, 4)


def test_rejects_non_integer_dimension() -> None:
    """shapeの要素が整数でなければ拒否する。

    以前は`int()`へ通していたので、
    文字列や小数がそのまま受け入れられていた。
    """
    entry = {"dtype": "F32", "shape": ["4"], "data_offsets": [0, 16]}
    with pytest.raises(ValueError, match="shape has a non-integer dimension"):
        parse_tensors({"x.weight": entry}, 16)


def test_rejects_non_array_offsets() -> None:
    """data_offsetsが配列でなければ拒否する。"""
    entry = {"dtype": "F32", "shape": [1], "data_offsets": 0}
    with pytest.raises(ValueError, match="data_offsets is not an array"):
        parse_tensors({"x.weight": entry}, 4)


def test_rejects_wrong_offsets_length() -> None:
    """data_offsetsが2要素でなければ拒否する。"""
    entry = {"dtype": "F32", "shape": [1], "data_offsets": [0, 4, 8]}
    with pytest.raises(ValueError, match="does not have two elements"):
        parse_tensors({"x.weight": entry}, 4)


def test_rejects_non_integer_offsets() -> None:
    """data_offsetsの要素が整数でなければ拒否する。"""
    entry = {"dtype": "F32", "shape": [1], "data_offsets": [0, "4"]}
    with pytest.raises(ValueError, match="data_offsets has a non-integer value"):
        parse_tensors({"x.weight": entry}, 4)


def test_rejects_gap_between_tensors() -> None:
    """テンソルの間に隙間があれば拒否する。

    隙間があると、順に読むだけではファイル全体を舐めたことにならず、
    検証を素通りする領域が生まれる。
    """
    first = {"dtype": "F32", "shape": [1], "data_offsets": [0, 4]}
    second = {"dtype": "F32", "shape": [1], "data_offsets": [8, 12]}
    with pytest.raises(ValueError, match="expected to start at 4"):
        parse_tensors({"x.weight": first, "y.weight": second}, 12)


def test_rejects_trailing_data() -> None:
    """テンソルが覆っていない余りがあれば拒否する。"""
    entry = {"dtype": "F32", "shape": [1], "data_offsets": [0, 4]}
    with pytest.raises(ValueError, match="data region is 8 bytes"):
        parse_tensors({"x.weight": entry}, 8)


def test_reports_broken_header_through_convert(tmp_path: Path) -> None:
    """コマンドの入口からでも同じ検証が効く。"""
    src = tmp_path / "broken.safetensors"
    save_raw_safetensors(
        src,
        {"x.weight": np.zeros(4, dtype="<f4")},
        dtype_names={"x.weight": "F4_E2M1"},
    )
    with pytest.raises(ValueError, match="unknown dtype"):
        convert(str(src), str(tmp_path / "dst.safetensors"), allow_overflow=False)
