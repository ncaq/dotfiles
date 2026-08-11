"""変換結果が変換元と対応していることを確かめる。

convertとは独立したコードパスにして、
同じ思い込みで両方が揃って間違えることを避ける。
"""

import os
from typing import BinaryIO

import numpy as np

from .format import (
    CHUNK_BYTES,
    Tensor,
    converted_dtype,
    drop_cache,
    open_tracked,
    read_exact,
    read_tensors,
    to_fp16,
)


def compare_headers(src: list[Tensor], dst: list[Tensor]) -> None:
    """テンソルの集合とshape、dtypeの対応が期待通りかを確かめる。"""
    src_by_name = {tensor.name: tensor for tensor in src}
    dst_by_name = {tensor.name: tensor for tensor in dst}
    if src_by_name.keys() != dst_by_name.keys():
        missing = sorted(src_by_name.keys() - dst_by_name.keys())
        extra = sorted(dst_by_name.keys() - src_by_name.keys())
        raise ValueError(f"tensor names differ: missing={missing} extra={extra}")
    for name, src_tensor in src_by_name.items():
        dst_tensor = dst_by_name[name]
        if src_tensor.shape != dst_tensor.shape:
            raise ValueError(
                f"{name}: shape {src_tensor.shape} became {dst_tensor.shape}"
            )
        expected = converted_dtype(src_tensor.dtype)
        if dst_tensor.dtype != expected:
            raise ValueError(
                f"{name}: dtype {src_tensor.dtype} became {dst_tensor.dtype}"
                f" instead of {expected}"
            )


def compare_contents(
    src_file: BinaryIO, dst_file: BinaryIO, src_tensor: Tensor
) -> None:
    """1つのテンソルの中身をチャンクごとに突き合わせる。

    比較はビットパターンで行うのでNaNの自己不一致は起きない。
    """
    src_fd = src_file.fileno()
    dst_fd = dst_file.fileno()
    remaining = src_tensor.size
    while 0 < remaining:
        count = min(remaining, CHUNK_BYTES)
        src_position = src_file.tell()
        dst_position = dst_file.tell()
        src_chunk = read_exact(src_file, count)
        if src_tensor.dtype == "F32":
            expected = to_fp16(src_chunk, allow_overflow=True).view("<u2")
            actual = np.frombuffer(read_exact(dst_file, count // 2), dtype="<u2")
            same = np.array_equal(expected, actual)
            dst_count = count // 2
        else:
            same = read_exact(dst_file, count) == src_chunk
            dst_count = count
        if not same:
            raise ValueError(
                f"{src_tensor.name}: contents differ at source offset {src_position}"
            )
        drop_cache(src_fd, src_position, count)
        drop_cache(dst_fd, dst_position, dst_count)
        remaining -= count


def verify(src_path: str, dst_path: str) -> None:
    """dstがsrcを変換したものであることを全要素の突き合わせで確かめる。

    サイズが合っていてもデータが1テンソル分ずれている、
    という最も危険な失敗を検出するために中身まで比較する。
    """
    with (
        open_tracked(src_path, f"verify {os.path.basename(src_path)}") as src_file,
        open(dst_path, "rb") as dst_file,
    ):
        src_metadata, src_tensors, src_start = read_tensors(src_path, src_file)
        dst_metadata, dst_tensors, dst_start = read_tensors(dst_path, dst_file)

        if src_metadata != dst_metadata:
            raise ValueError("__metadata__ differs")
        compare_headers(src_tensors, dst_tensors)

        dst_by_name = {tensor.name: tensor for tensor in dst_tensors}
        for src_tensor in src_tensors:
            dst_tensor = dst_by_name[src_tensor.name]
            src_file.seek(src_start + src_tensor.begin)
            dst_file.seek(dst_start + dst_tensor.begin)
            compare_contents(src_file, dst_file, src_tensor)
