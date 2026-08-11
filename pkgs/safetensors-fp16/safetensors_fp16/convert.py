"""safetensorsのF32テンソルだけをF16へ変換する。

ComfyUIのDynamicVRAMはモデルの重みをホストのpinned memoryへ置くが、
そのサイズはmmapしたファイル上のdtypeを基準に決まる。
計算dtypeがfp16でもファイルがfp32ならpinned memoryは倍必要になり、
14.29Bパラメータのモデルではホストのメモリを食い尽くす。
ファイル側を事前にfp16へ落とすことでこれを半分にする。

fp32からfp16への丸めはIEEE 754のround-to-nearest-evenで、
ComfyUIがランタイムで行うキャストとビット単位で一致するため、
生成結果は変わらない。
"""

import os
import struct

from .format import (
    CHUNK_BYTES,
    SyncedWriter,
    build_header,
    drop_cache,
    open_tracked,
    read_exact,
    read_tensors,
    to_fp16,
)


def convert(src_path: str, dst_path: str, allow_overflow: bool) -> None:
    """srcのF32テンソルだけをF16へ変換してdstへ書く。"""
    with (
        open_tracked(src_path, f"convert {os.path.basename(src_path)}") as src_file,
        open(dst_path, "wb") as dst_file,
    ):
        metadata, tensors, data_start = read_tensors(src_path, src_file)
        raw_header, out_tensors = build_header(metadata, tensors)

        writer = SyncedWriter(dst_file)
        writer.write(struct.pack("<Q", len(raw_header)))
        writer.write(raw_header)

        src_fd = src_file.fileno()
        for tensor in tensors:
            src_file.seek(data_start + tensor.begin)
            remaining = tensor.size
            while 0 < remaining:
                count = min(remaining, CHUNK_BYTES)
                position = src_file.tell()
                chunk = read_exact(src_file, count)
                if tensor.dtype == "F32":
                    writer.write(to_fp16(chunk, allow_overflow))
                else:
                    writer.write(chunk)
                drop_cache(src_fd, position, count)
                remaining -= count
        writer.sync()

    expected_size = 8 + len(raw_header) + sum(tensor.size for tensor in out_tensors)
    actual_size = os.path.getsize(dst_path)
    if actual_size != expected_size:
        raise ValueError(f"wrote {actual_size} bytes but expected {expected_size}")
