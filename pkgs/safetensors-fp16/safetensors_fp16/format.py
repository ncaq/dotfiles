"""safetensorsのフォーマットを読み書きするための共通部分。

safetensorsライブラリは使わない。
Python APIは全テンソルの辞書をメモリに要求する設計で数十GBのファイルには使えず、
フォーマット自体は「8バイトのu64ヘッダ長 + JSONヘッダ + 連続したデータ」だけなので、
自前で読み書きしてストリーミング処理する。
"""

import json
import math
import os
import struct
from collections.abc import Buffer, Generator
from contextlib import contextmanager
from typing import BinaryIO, NamedTuple, cast

import numpy as np
from tqdm import tqdm

# safetensorsのdtype名から1要素あたりのバイト数への対応。
# ここに無いdtypeはサイズを検証できないので、黙って素通しせずエラーにする。
DTYPE_SIZE: dict[str, int] = {
    "BOOL": 1,
    "U8": 1,
    "I8": 1,
    "F8_E4M3": 1,
    "F8_E5M2": 1,
    "I16": 2,
    "U16": 2,
    "F16": 2,
    "BF16": 2,
    "I32": 4,
    "U32": 4,
    "F32": 4,
    "I64": 8,
    "U64": 8,
    "F64": 8,
}

# ヘッダとして受け付ける最大の長さ。
#
# ヘッダ長は先頭8バイトのu64をそのまま読むので、
# 検証せずに`read`へ渡すと細工されたファイルで巨大な確保が起きる。
# このコマンドは`lib/convert-safetensors-fp16.nix`から外部配布のモデルを処理するため、
# 数十バイトのファイルだけでビルドホストのメモリを枯渇させられてしまう。
# 本家のsafetensorsが同じ理由で設けている100MBに揃える。
HEADER_MAX_BYTES = 100 * 1000 * 1000

# ヘッダの直後からデータが8バイト境界で始まるようにするパディング単位。
# 公式のシリアライザと同じ規約で、mmapしたテンソルのアライメントを保つ。
HEADER_ALIGN = 8

# 一度に読み書きするバイト数。
# テンソル単位ではなくこの固定長で区切ることで、
# 単体で数百MBあるテンソルでもピークメモリが読めるようになる。
# F32とF16のどちらでも割り切れる必要がある。
CHUNK_BYTES = 64 * 1024 * 1024

# 書き込んだ範囲をfdatasyncしてページキャッシュから落とす間隔。
SYNC_INTERVAL_BYTES = 1024 * 1024 * 1024

# 進捗表示を更新する最短間隔の秒数。
# ビルドログが流れ続けることで生存確認になり、max-silent-time対策にもなる。
PROGRESS_INTERVAL_SECONDS = 10.0


class Tensor(NamedTuple):
    """ヘッダに記述された1つのテンソルの位置と型。"""

    name: str
    dtype: str
    shape: list[int]
    begin: int
    end: int

    @property
    def size(self) -> int:
        return self.end - self.begin


def drop_cache(fd: int, offset: int, length: int) -> None:
    """処理し終えた範囲をページキャッシュから落とす。

    数十GBを素通しするとキャッシュがほぼ総入れ替えになり、
    複数の変換が並走するとホストの他の処理を巻き添えにするため明示的に捨てる。
    """
    if length <= 0:
        return
    os.posix_fadvise(fd, offset, length, os.POSIX_FADV_DONTNEED)


@contextmanager
def open_tracked(path: str, label: str) -> Generator[BinaryIO]:
    """読み込み量に応じた進捗を表示しながらファイルを開く。

    tqdmがreadを横取りして数えるので、呼び出し側は進捗を意識しなくてよい。
    """
    with (
        open(path, "rb") as raw,
        # typeshedのtqdmスタブは`**tqdm_kwargs`を無注釈のまま受けるため、
        # スタブを入れてもこの呼び出しの型は部分的に不明のままになる。
        tqdm.wrapattr(  # pyright: ignore[reportUnknownMemberType]
            raw,
            "read",
            total=os.path.getsize(path),
            desc=label,
            mininterval=PROGRESS_INTERVAL_SECONDS,
        ) as tracked,
    ):
        # tqdmが返すラッパーの型はreadしか宣言していないが、
        # 実体は残りの操作を元のファイルへ委譲するのでBinaryIOとして扱える。
        yield cast(BinaryIO, tracked)


class SyncedWriter:
    """書き込んだ範囲を定期的にfdatasyncしてページキャッシュから落とすラッパー。

    dirtyなページにはposix_fadviseのDONTNEEDが効かないため、
    先にfdatasyncしてからでないと捨てられない。
    """

    def __init__(self, file: BinaryIO, interval: int = SYNC_INTERVAL_BYTES) -> None:
        self.file = file
        self.interval = interval
        self.dropped = 0

    def write(self, data: Buffer) -> None:
        self.file.write(data)
        if self.file.tell() - self.dropped >= self.interval:
            self.sync()

    def sync(self) -> None:
        self.file.flush()
        fd = self.file.fileno()
        os.fdatasync(fd)
        position = self.file.tell()
        drop_cache(fd, self.dropped, position - self.dropped)
        self.dropped = position


def json_object(value: object, message: str) -> dict[str, object]:
    """JSONのオブジェクトを、値の型が分かる形で取り出す。

    `isinstance(value, dict)`だけでは要素の型が不明なままになり、
    取り出した先を型検査が見てくれない。
    JSONのオブジェクトはキーが文字列で値は何であってもよいので、
    `dict[str, object]`へ寄せる。
    """
    if not isinstance(value, dict):
        raise ValueError(message)
    return cast(dict[str, object], value)


def json_list(value: object, message: str) -> list[object]:
    """JSONの配列を、要素の型が分かる形で取り出す。"""
    if not isinstance(value, list):
        raise ValueError(message)
    return cast(list[object], value)


def json_int(value: object, message: str) -> int:
    """JSONの整数を取り出す。

    元は`int()`に通していたが、
    それだと文字列や小数も黙って受け入れてしまう。
    shapeとdata_offsetsは仕様上どちらも整数なので、
    整数でなければ何が壊れているのか分かる形で落とす。
    """
    if not isinstance(value, int):
        raise ValueError(message)
    return value


def read_header(file: BinaryIO) -> tuple[dict[str, object], int]:
    """先頭のヘッダを読み、JSONとデータ領域の開始位置を返す。"""
    raw_length = file.read(8)
    if len(raw_length) != 8:
        raise ValueError("file is too short to contain a safetensors header")
    # struct.unpackの戻り値は要素の型が決まらないので、u64だと分かっている型を宣言する。
    header_length: int = struct.unpack("<Q", raw_length)[0]
    # 確保する前に弾く。読んでから長さを確かめるのでは手遅れになる。
    if HEADER_MAX_BYTES < header_length:
        raise ValueError(
            f"header claims {header_length} bytes"
            f" but at most {HEADER_MAX_BYTES} is accepted"
        )
    raw_header = file.read(header_length)
    if len(raw_header) != header_length:
        raise ValueError("header is truncated")
    data_start = 8 + header_length
    if data_start % HEADER_ALIGN != 0:
        raise ValueError(f"data does not start at a {HEADER_ALIGN} byte boundary")
    header = json_object(json.loads(raw_header), "header is not a JSON object")
    return header, data_start


def parse_tensors(
    header: dict[str, object], data_size: int
) -> tuple[dict[str, object] | None, list[Tensor]]:
    """ヘッダから__metadata__を分離し、テンソルをデータの配置順に検証しながら並べる。

    オフセットが0から隙間なく連続していることまで確認する。
    ここを通せば、後段は各テンソルを順に読むだけでファイル全体を舐めたことになる。
    """
    raw_metadata = header.get("__metadata__")
    metadata = (
        None
        if raw_metadata is None
        else json_object(raw_metadata, "__metadata__ is not a JSON object")
    )

    tensors: list[Tensor] = []
    for name, info in header.items():
        if name == "__metadata__":
            continue
        entry = json_object(info, f"{name}: entry is not a JSON object")
        dtype = entry["dtype"]
        if not isinstance(dtype, str) or dtype not in DTYPE_SIZE:
            raise ValueError(f"{name}: unknown dtype {dtype}")
        shape = [
            json_int(dimension, f"{name}: shape has a non-integer dimension")
            for dimension in json_list(entry["shape"], f"{name}: shape is not an array")
        ]
        offsets = json_list(
            entry["data_offsets"], f"{name}: data_offsets is not an array"
        )
        if len(offsets) != 2:
            raise ValueError(f"{name}: data_offsets does not have two elements")
        begin = json_int(offsets[0], f"{name}: data_offsets has a non-integer value")
        end = json_int(offsets[1], f"{name}: data_offsets has a non-integer value")
        expected = math.prod(shape) * DTYPE_SIZE[dtype]
        if end - begin != expected:
            raise ValueError(
                f"{name}: data_offsets span {end - begin} bytes"
                f" but shape and dtype need {expected}"
            )
        tensors.append(
            Tensor(name=name, dtype=dtype, shape=shape, begin=begin, end=end)
        )

    tensors.sort(key=lambda tensor: tensor.begin)
    offset = 0
    for tensor in tensors:
        if tensor.begin != offset:
            raise ValueError(
                f"{tensor.name}: expected to start at {offset} but starts at"
                f" {tensor.begin}"
            )
        offset = tensor.end
    if offset != data_size:
        raise ValueError(f"data region is {data_size} bytes but tensors span {offset}")
    return metadata, tensors


def read_tensors(
    path: str, file: BinaryIO
) -> tuple[dict[str, object] | None, list[Tensor], int]:
    """ヘッダを読んで__metadata__とテンソル列とデータ開始位置を返す。"""
    header, data_start = read_header(file)
    metadata, tensors = parse_tensors(header, os.path.getsize(path) - data_start)
    return metadata, tensors, data_start


def converted_dtype(dtype: str) -> str:
    """変換後のdtype名を返す。F32だけがF16になる。"""
    return "F16" if dtype == "F32" else dtype


def build_header(
    metadata: dict[str, object] | None, tensors: list[Tensor]
) -> tuple[bytes, list[Tensor]]:
    """F32をF16へ置き換えた出力用のヘッダと、新しいオフセットを持つテンソル列を返す。

    テンソルは入力のデータ配置順のまま並べる。
    名前で並べ直さないので、出力は入力ファイルから一意に決まる。
    """
    header: dict[str, object] = {}
    if metadata is not None:
        header["__metadata__"] = metadata

    out_tensors: list[Tensor] = []
    offset = 0
    for tensor in tensors:
        dtype = converted_dtype(tensor.dtype)
        size = tensor.size // 2 if tensor.dtype == "F32" else tensor.size
        header[tensor.name] = {
            "dtype": dtype,
            "shape": tensor.shape,
            "data_offsets": [offset, offset + size],
        }
        out_tensors.append(
            Tensor(
                name=tensor.name,
                dtype=dtype,
                shape=tensor.shape,
                begin=offset,
                end=offset + size,
            )
        )
        offset += size

    raw_header = json.dumps(header, separators=(",", ":")).encode("utf-8")
    padding = -(8 + len(raw_header)) % HEADER_ALIGN
    return raw_header + b" " * padding, out_tensors


def to_fp16(chunk: bytes, allow_overflow: bool) -> np.ndarray:
    """F32のバイト列をF16の配列へ変換する。

    fp16の表現範囲を超えて新たにinfになる要素があれば既定では失敗させる。
    静かにinfへ潰れた重みは壊れたモデルになるので、
    bf16にするかfp32のままにするかを人間が判断すべきだからである。
    入力に元からあるinfやNaN、アンダーフローでは発火しない。
    """
    over = "ignore" if allow_overflow else "raise"
    with np.errstate(over=over, under="ignore", invalid="ignore"):
        return np.frombuffer(chunk, dtype="<f4").astype("<f2")


def read_exact(file: BinaryIO, count: int) -> bytes:
    """指定したバイト数をちょうど読む。足りなければエラーにする。"""
    chunk = file.read(count)
    if len(chunk) != count:
        raise ValueError(f"expected {count} bytes but read {len(chunk)}")
    return chunk
