#!/usr/bin/env python3
"""GGUFファイルのtokenizer.chat_templateへ文字列置換をin-placeで適用する。

使い方: patch-gguf-chat-template.py <gguf-path> <replacements-json>

replacements-jsonは`[{"from": "...", "to": "..."}, ...]`のリスト。
各fromはテンプレート中にちょうど1回現れる必要があり、
見つからない場合は何も書き込まずに異常終了する。

GGUFのメタデータ文字列は長さプレフィックス付きで、
長さを変えるとファイル全体の書き直しになるため、
置換後のテンプレートは元と同じバイト長に保つ。
縮んだ分は末尾にJinjaコメントを付けてパディングする。
伸びる置換は適用できないので異常終了する。
"""

import json
import struct
import sys
from typing import BinaryIO

GGUF_MAGIC = b"GGUF"

# GGUF value type -> 固定サイズ(バイト)。string(8)とarray(9)は可変。
FIXED_SIZE = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}


def read_str(f: BinaryIO) -> bytes:
    (n,) = struct.unpack("<Q", f.read(8))
    return f.read(n)


def skip_value(f: BinaryIO, vtype: int) -> None:
    if vtype in FIXED_SIZE:
        f.seek(FIXED_SIZE[vtype], 1)
    elif vtype == 8:
        (n,) = struct.unpack("<Q", f.read(8))
        f.seek(n, 1)
    elif vtype == 9:
        etype, count = struct.unpack("<IQ", f.read(12))
        if etype in FIXED_SIZE:
            f.seek(FIXED_SIZE[etype] * count, 1)
        elif etype == 8:
            for _ in range(count):
                (n,) = struct.unpack("<Q", f.read(8))
                f.seek(n, 1)
        else:
            raise ValueError(f"nested array unsupported: {etype}")
    else:
        raise ValueError(f"unknown value type: {vtype}")


def apply_replacements(template: bytes, replacements: list[dict[str, str]]) -> bytes:
    n = len(template)
    for r in replacements:
        old = r["from"].encode()
        new = r["to"].encode()
        count = template.count(old)
        if count != 1:
            raise SystemExit(
                f"replacement source found {count} times (expected 1): {r['from']!r}"
            )
        template = template.replace(old, new)
    pad = n - len(template)
    if pad < 0:
        raise SystemExit(f"patched template is longer than original by {-pad} bytes")
    if pad > 0:
        if pad < 6:
            raise SystemExit(f"padding {pad} is too small for a Jinja comment")
        template = template + b"{#" + b" " * (pad - 4) + b"#}"
    return template


def main() -> None:
    gguf_path = sys.argv[1]
    with open(sys.argv[2]) as jf:
        replacements: list[dict[str, str]] = json.load(jf)

    with open(gguf_path, "r+b") as f:
        if f.read(4) != GGUF_MAGIC:
            raise SystemExit("not a GGUF file")
        (version,) = struct.unpack("<I", f.read(4))
        if version != 3:
            raise SystemExit(f"unexpected GGUF version {version}")
        _tensor_count, kv_count = struct.unpack("<QQ", f.read(16))

        for _ in range(kv_count):
            key = read_str(f)
            (vtype,) = struct.unpack("<I", f.read(4))
            if key == b"tokenizer.chat_template":
                if vtype != 8:
                    raise SystemExit(f"chat_template is not a string: type {vtype}")
                (n,) = struct.unpack("<Q", f.read(8))
                pos = f.tell()
                template = f.read(n)
                patched = apply_replacements(template, replacements)
                assert len(patched) == n
                f.seek(pos)
                f.write(patched)
                print(f"patched tokenizer.chat_template at offset {pos}, {n} bytes")
                return
            skip_value(f, vtype)
    raise SystemExit("tokenizer.chat_template not found")


if __name__ == "__main__":
    main()
