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

import pytest
from conftest import write_header

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


@pytest.mark.parametrize("dimension", ["4", 4.0, True, -2])
def test_rejects_invalid_dimension(dimension: object) -> None:
    """shapeの要素が非負整数でなければ拒否する。

    `bool`は`int`の派生なのでJSONの`true`が1として通り得る。
    負の次元は偶数個あれば`math.prod`が正になり、
    オフセットの整合検証も連続性の検証も素通りし得る。
    """
    entry = {"dtype": "F32", "shape": [dimension], "data_offsets": [0, 16]}
    with pytest.raises(ValueError, match="shape element is not a non-negative integer"):
        parse_tensors({"x.weight": entry}, 16)


def test_rejects_negative_dimensions_that_multiply_to_positive() -> None:
    """負の次元が偶数個でも拒否する。

    -2が2つならmath.prodは4になり、
    dtypeと合わせた16バイトがdata_offsetsと一致してしまうため、
    次元単体を見ていないと最後まで通ってしまう組み合わせ。
    """
    entry = {"dtype": "F32", "shape": [-2, -2], "data_offsets": [0, 16]}
    with pytest.raises(ValueError, match="shape element is not a non-negative integer"):
        parse_tensors({"x.weight": entry}, 16)


@pytest.mark.parametrize("key", ["dtype", "shape", "data_offsets"])
def test_rejects_missing_entry_key(key: str) -> None:
    """テンソルの記述にキーが欠けていれば、どのキーが無いか分かる形で拒否する。"""
    entry: dict[str, object] = {
        "dtype": "F32",
        "shape": [1],
        "data_offsets": [0, 4],
    }
    del entry[key]
    with pytest.raises(ValueError, match=f"entry has no {key}"):
        parse_tensors({"x.weight": entry}, 4)


def test_rejects_invalid_json_header(tmp_path: Path) -> None:
    """ヘッダがJSONとして壊れていれば、そうと分かる形で拒否する。

    `JSONDecodeError`のままでは`Expecting value: line 1 column 1`となり、
    safetensorsのヘッダの話だと読み取れない。
    """
    path = tmp_path / "broken-json.safetensors"
    raw = b"not json"
    raw += b" " * (-(8 + len(raw)) % 8)
    path.write_bytes(len(raw).to_bytes(8, "little") + raw)
    with (
        path.open("rb") as file,
        pytest.raises(ValueError, match="header is not valid JSON"),
    ):
        read_header(file)


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


@pytest.mark.parametrize("offset", ["4", 4.0, True, -4])
def test_rejects_invalid_offsets(offset: object) -> None:
    """data_offsetsの要素が非負整数でなければ拒否する。"""
    entry = {"dtype": "F32", "shape": [1], "data_offsets": [0, offset]}
    with pytest.raises(
        ValueError, match="data_offsets element is not a non-negative integer"
    ):
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
    """コマンドの入口からでも同じ検証が効く。

    `test_convert.py`が見ているのはdtypeとオフセットの食い違いなので、
    ここではそちらを通らないshapeの検証を選ぶ。
    """
    src = tmp_path / "broken.safetensors"
    write_header(
        src,
        {"x.weight": {"dtype": "F32", "shape": ["4"], "data_offsets": [0, 16]}},
        b"\x00" * 16,
    )
    with pytest.raises(ValueError, match="shape element is not a non-negative integer"):
        convert(str(src), str(tmp_path / "dst.safetensors"), allow_overflow=False)
