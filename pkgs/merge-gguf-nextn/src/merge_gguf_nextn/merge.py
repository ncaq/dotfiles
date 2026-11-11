"""本体のGGUFとNextN層だけを持つGGUFを1つのGGUFへまとめる。

ggml-orgはQwen3.8-27Bを変換する時に、
MTPのドラフトヘッドであるNextN層を`mtp-*.gguf`として本体から切り離して配っている。
llama.cppは`-md`で別ファイルのドラフトヘッドを読めるが、
OllamaのModelfileにはドラフトを指定する構文が無いため、
同じGGUFの中に入っていないとOllamaからは投機的デコーディングが使えない。

ドラフトヘッドのGGUFは本体と同じアーキテクチャのメタデータを持ち、
`block_count`は本体の層数にNextN層の数を足した値になっている。
NextN層のテンソルは本体の最後の層の次の番号の`blk.N.`で始まる。
本体と共有する埋め込みや出力のテンソルも一緒に入っているが、
それは本体のものをそのまま使う。

まとめたファイルは、
本体のメタデータのうち層数と層ごとの配列だけをドラフトヘッドの値へ差し替え、
NextN層の数を足したものになる。
テンソルは本体の全てに、ドラフトヘッドのNextN層を後ろへ並べる。
変換時にNextN層を捨てずに本体と一緒に書き出した場合と同じ形である。
"""

from collections.abc import Iterable
from pathlib import Path

import gguf
import numpy as np


class MergeError(Exception):
    """本体とドラフトヘッドが同じモデルから作られた組として噛み合わない。"""


def _field(reader: gguf.GGUFReader, key: str) -> gguf.ReaderField | None:
    return reader.get_field(key)


def _architecture(reader: gguf.GGUFReader, path: Path) -> str:
    field = _field(reader, gguf.Keys.General.ARCHITECTURE)
    if field is None:
        raise MergeError(f"{path}にアーキテクチャのメタデータがありません")
    return str(field.contents())


def _uint(reader: gguf.GGUFReader, key: str) -> int | None:
    field = _field(reader, key)
    if field is None:
        return None
    return int(field.contents())


def _is_array(field: gguf.ReaderField) -> bool:
    return field.types[0] == gguf.GGUFValueType.ARRAY


def _copy_field(writer: gguf.GGUFWriter, field: gguf.ReaderField) -> None:
    value_type = field.types[0]
    sub_type = field.types[-1] if value_type == gguf.GGUFValueType.ARRAY else None
    writer.add_key_value(field.name, field.contents(), value_type, sub_type=sub_type)


def _per_layer_overrides(
    main: gguf.GGUFReader,
    draft: gguf.GGUFReader,
    arch: str,
    main_blocks: int,
    draft_blocks: int,
) -> dict[str, gguf.ReaderField]:
    """層ごとの値を並べた配列のうち、ドラフトヘッドの値へ差し替えるものを返す。

    Qwen3.8の`attention.recurrent_layers`のように、
    層の数だけ要素を持つ配列はNextN層の分だけ伸ばす必要がある。
    本体の層に当たる前半が本体と一致することを確かめて、
    違うモデルの組を黙ってまとめないようにする。

    本体の層の数だけ要素を持つ配列がドラフトヘッドで伸びていない時も失敗にする。
    そのまま本体の値を写すと、
    `block_count`だけが増えて配列の長さと食い違うためである。
    """
    overrides: dict[str, gguf.ReaderField] = {}
    for field in draft.fields.values():
        if not field.name.startswith(f"{arch}.") or not _is_array(field):
            continue
        if len(field.data) != draft_blocks:
            continue
        main_field = _field(main, field.name)
        if main_field is None:
            raise MergeError(f"本体に層ごとの配列`{field.name}`がありません")
        main_values: list[object] = list(main_field.contents())
        draft_values: list[object] = list(field.contents())
        if len(main_values) != main_blocks or draft_values[:main_blocks] != main_values:
            raise MergeError(
                f"層ごとの配列`{field.name}`の本体の層に当たる値が本体と一致しません"
            )
        overrides[field.name] = field
    for field in main.fields.values():
        if (
            field.name.startswith(f"{arch}.")
            and _is_array(field)
            and len(field.data) == main_blocks
            and field.name not in overrides
        ):
            raise MergeError(
                f"本体の層ごとの配列`{field.name}`がドラフトヘッドで伸びていません"
            )
    return overrides


_COMPARE_CHUNK_BYTES = 64 * 1024 * 1024


def same_bytes(
    a: np.ndarray, b: np.ndarray, chunk_bytes: int = _COMPARE_CHUNK_BYTES
) -> bool:
    """2つの配列がバイト列として同じかを、少しずつ比べて確かめる。

    `np.array_equal`に丸ごと渡すと要素数と同じ大きさのbool配列を一度に確保する。
    Qwen3.8-27Bの埋め込みのテンソルはBF16で約2.5GBあり、
    ビルドのメモリのピークがその分だけ増えるので、
    `chunk_bytes`ずつ比べて最初に違ったところで打ち切る。
    """
    a_bytes = a.reshape(-1).view(np.uint8)
    b_bytes = b.reshape(-1).view(np.uint8)
    if a_bytes.size != b_bytes.size:
        return False
    return all(
        np.array_equal(a_bytes[i : i + chunk_bytes], b_bytes[i : i + chunk_bytes])
        for i in range(0, a_bytes.size, chunk_bytes)
    )


def _check_shared_tensors(
    main_tensors: dict[str, gguf.ReaderTensor],
    shared: Iterable[gguf.ReaderTensor],
) -> None:
    """ドラフトヘッドが持つ本体と共有のテンソルが、本体のものとバイト単位で同じか確かめる。

    埋め込みや出力のテンソルが一致すれば、
    両者が同じ重みを同じ方法で変換したものだと分かる。
    別のモデルや別の版のドラフトヘッドを足すと、
    ロードはできても受理率が落ちるだけで誤りに気付けない。
    """
    for tensor in shared:
        counterpart = main_tensors.get(tensor.name)
        if counterpart is None:
            raise MergeError(
                f"ドラフトヘッドのテンソル`{tensor.name}`が本体にありません"
            )
        if counterpart.tensor_type != tensor.tensor_type or not np.array_equal(
            counterpart.shape, tensor.shape
        ):
            raise MergeError(f"テンソル`{tensor.name}`の型か形が本体と違います")
        if not same_bytes(counterpart.data, tensor.data):
            raise MergeError(f"テンソル`{tensor.name}`の中身が本体と違います")


def merge(main_path: Path, draft_path: Path, output_path: Path) -> None:
    """`main_path`の本体へ`draft_path`のNextN層を足したGGUFを`output_path`へ書く。"""
    main = gguf.GGUFReader(main_path)
    draft = gguf.GGUFReader(draft_path)

    arch = _architecture(main, main_path)
    if _architecture(draft, draft_path) != arch:
        raise MergeError("本体とドラフトヘッドのアーキテクチャが違います")

    block_count_key = f"{arch}.block_count"
    nextn_key = f"{arch}.nextn_predict_layers"
    main_blocks = _uint(main, block_count_key)
    draft_blocks = _uint(draft, block_count_key)
    nextn_layers = _uint(draft, nextn_key)
    if main_blocks is None or draft_blocks is None:
        raise MergeError(f"`{block_count_key}`がありません")
    if _uint(main, nextn_key):
        raise MergeError("本体が既にNextN層を持っています")
    if not nextn_layers:
        raise MergeError("ドラフトヘッドにNextN層がありません")
    if draft_blocks != main_blocks + nextn_layers:
        raise MergeError(
            f"ドラフトヘッドの層数{draft_blocks}が"
            f"本体の層数{main_blocks}とNextN層の数{nextn_layers}の和と一致しません"
        )

    nextn_prefixes = tuple(f"blk.{i}." for i in range(main_blocks, draft_blocks))
    main_tensors = {tensor.name: tensor for tensor in main.tensors}
    nextn_tensors = [
        tensor for tensor in draft.tensors if tensor.name.startswith(nextn_prefixes)
    ]
    if not nextn_tensors:
        raise MergeError("ドラフトヘッドにNextN層のテンソルがありません")
    if any(name.startswith(nextn_prefixes) for name in main_tensors):
        raise MergeError("本体が既にNextN層の番号のテンソルを持っています")
    _check_shared_tensors(
        main_tensors,
        (
            tensor
            for tensor in draft.tensors
            if not tensor.name.startswith(nextn_prefixes)
        ),
    )

    overrides = _per_layer_overrides(main, draft, arch, main_blocks, draft_blocks)
    for key in (block_count_key, nextn_key):
        field = _field(draft, key)
        assert field is not None
        overrides[key] = field

    writer = gguf.GGUFWriter(output_path, arch, endianess=main.endianess)
    for field in main.fields.values():
        # アーキテクチャと`GGUF.`で始まる仮想的なフィールドはwriterが自分で書く。
        if field.name == gguf.Keys.General.ARCHITECTURE or field.name.startswith(
            "GGUF."
        ):
            continue
        _copy_field(writer, overrides.pop(field.name, field))
    # 本体に無かったキー、つまりNextN層の数を後ろへ足す。
    for field in overrides.values():
        _copy_field(writer, field)

    tensors = [*main.tensors, *nextn_tensors]
    for tensor in tensors:
        writer.add_tensor_info(
            tensor.name,
            tensor.data.shape,
            tensor.data.dtype,
            tensor.data.nbytes,
            tensor.tensor_type,
        )
    writer.write_header_to_file()
    writer.write_kv_data_to_file()
    writer.write_ti_data_to_file()
    for tensor in tensors:
        writer.write_tensor_data(tensor.data, tensor_endianess=main.endianess)
    writer.close()
