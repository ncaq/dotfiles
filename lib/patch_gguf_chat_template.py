#!/usr/bin/env python3
"""GGUFファイルの`tokenizer.chat_template`を取り出して書き戻す。

    patch_gguf_chat_template.py extract <gguf-path> <template-path>
    patch_gguf_chat_template.py embed <gguf-path> <template-path>

`extract`で取り出したテンプレートへ`patch`コマンドで差分を当て、
`embed`で同じGGUFへ書き戻すことを想定している。
差分の適用自体はこのスクリプトの仕事ではない。

GGUFのメタデータ文字列は長さプレフィックス付きで並んでいる。
長さを変えるとそれ以降の全てのオフセットがずれてファイル全体の書き直しになるため、
`embed`は元と同じバイト長に保ったまま上書きする。
縮んだ分は末尾へJinjaのコメントを足して埋める。
コメントは描画結果に何も足さないので、
埋めた分がプロンプトに現れることはない。
伸びた場合は埋めようがないので異常終了する。
その場合は差分の側を短く書き直す必要がある。
"""

import argparse
import os
import struct
from pathlib import Path
from typing import BinaryIO

GGUF_MAGIC = b"GGUF"
# 対応するのはGGUF v3だけ。
# v2以前はメタデータの長さがuint32で、読み取りのフォーマット文字列から違う。
GGUF_VERSION = 3

CHAT_TEMPLATE_KEY = b"tokenizer.chat_template"

# 可変長の値の型ID。
# これ以外の型は`FIXED_SIZE`が長さを持っている。
TYPE_STRING = 8
TYPE_ARRAY = 9

# 固定長の値の型IDとそのバイト数。
# 順にuint8, int8, uint16, int16, uint32, int32, float32, bool, uint64, int64, float64。
FIXED_SIZE = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}

# Jinjaのコメントは`{#`と`#}`で4バイト使う。
# これ未満の端数は埋めようがない。
COMMENT_OVERHEAD = 4


def read_exact(file: BinaryIO, size: int) -> bytes:
    """指定したバイト数をちょうど読む。

    途中で切れたファイルでは`read`が短く返る。
    そのまま`struct.unpack`へ渡すと`struct.error`のtracebackになり、
    他の異常系が出す説明と扱いが揃わない。
    """
    data = file.read(size)
    if len(data) != size:
        raise SystemExit(f"unexpected end of file: wanted {size}, got {len(data)}")
    return data


def check_span(file: BinaryIO, length: int) -> int:
    """これから読み飛ばす長さがファイルの残りに収まっているか確かめる。

    長さプレフィックスはファイルから読んだ値であり、
    壊れたファイルでは任意の値が入っている。
    `read`へそのまま渡すと巨大なメモリ確保になり、
    `seek`は末尾を越えても成功してしまう。
    どちらもオフセットを静かに壊すので、
    走査を続けずに止める。
    """
    remaining = os.fstat(file.fileno()).st_size - file.tell()
    if not 0 <= length <= remaining:
        raise SystemExit(f"length {length} exceeds the remaining {remaining} bytes")
    return length


def read_length(file: BinaryIO) -> int:
    """長さプレフィックスを1つ読んで検証する。"""
    (length,) = struct.unpack("<Q", read_exact(file, 8))
    return check_span(file, length)


def read_string(file: BinaryIO) -> bytes:
    """長さプレフィックス付きの文字列を1つ読む。"""
    return read_exact(file, read_length(file))


def skip_value(file: BinaryIO, value_type: int) -> None:
    """値を1つ読み飛ばす。"""
    if value_type in FIXED_SIZE:
        file.seek(check_span(file, FIXED_SIZE[value_type]), 1)
    elif value_type == TYPE_STRING:
        file.seek(read_length(file), 1)
    elif value_type == TYPE_ARRAY:
        element_type, count = struct.unpack("<IQ", read_exact(file, 12))
        if element_type in FIXED_SIZE:
            file.seek(check_span(file, FIXED_SIZE[element_type] * count), 1)
        elif element_type == TYPE_STRING:
            # 要素ごとに長さが違うのでまとめては飛ばせない。
            # `tokenizer.ggml.tokens`がこれで、語彙の数だけ繰り返す。
            for _ in range(count):
                file.seek(read_length(file), 1)
        else:
            # 配列の配列はGGUFの仕様には書けるが実物を見たことがない。
            # 黙って読み飛ばすとオフセットがずれるので、読めないと言って止まる。
            raise SystemExit(f"nested array unsupported: {element_type}")
    else:
        raise SystemExit(f"unknown value type: {value_type}")


def find_chat_template(file: BinaryIO) -> tuple[int, int]:
    """`tokenizer.chat_template`の値のオフセットとバイト長を返す。"""
    if file.read(4) != GGUF_MAGIC:
        raise SystemExit("not a GGUF file")
    (version,) = struct.unpack("<I", read_exact(file, 4))
    if version != GGUF_VERSION:
        raise SystemExit(f"unexpected GGUF version {version}")
    # ヘッダはテンソル数とメタデータ数がこの順に並ぶ。
    # テンソルは読まないのでメタデータ数だけ取る。
    kv_count = struct.unpack("<QQ", read_exact(file, 16))[1]

    for _ in range(kv_count):
        key = read_string(file)
        (value_type,) = struct.unpack("<I", read_exact(file, 4))
        if key != CHAT_TEMPLATE_KEY:
            skip_value(file, value_type)
            continue
        if value_type != TYPE_STRING:
            raise SystemExit(f"chat_template is not a string: type {value_type}")
        length = read_length(file)
        return file.tell(), length
    raise SystemExit("tokenizer.chat_template not found")


def pad_to_length(template: bytes, length: int) -> bytes:
    """末尾へJinjaのコメントを足して元のバイト長へ揃える。"""
    padding = length - len(template)
    if padding < 0:
        raise SystemExit(
            f"patched template is longer than original by {-padding} bytes"
        )
    if padding == 0:
        return template
    if padding < COMMENT_OVERHEAD:
        raise SystemExit(f"padding of {padding} bytes is too small for a Jinja comment")
    return template + b"{#" + b" " * (padding - COMMENT_OVERHEAD) + b"#}"


def extract(gguf_path: str, template_path: str) -> None:
    """GGUFからチャットテンプレートを取り出してファイルへ書く。"""
    with open(gguf_path, "rb") as file:
        offset, length = find_chat_template(file)
        file.seek(offset)
        template = file.read(length)
    Path(template_path).write_bytes(template)
    print(f"extracted tokenizer.chat_template: offset {offset}, {length} bytes")


def embed(gguf_path: str, template_path: str) -> None:
    """ファイルのチャットテンプレートをGGUFへ書き戻す。"""
    template = Path(template_path).read_bytes()
    with open(gguf_path, "r+b") as file:
        offset, length = find_chat_template(file)
        file.seek(offset)
        file.write(pad_to_length(template, length))
    print(f"embedded tokenizer.chat_template: offset {offset}, {length} bytes")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="GGUFの`tokenizer.chat_template`を取り出して書き戻す。"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    extract_parser = subparsers.add_parser(
        "extract", help="GGUFからテンプレートを取り出す。"
    )
    extract_parser.add_argument("gguf", help="対象のGGUFファイル。")
    extract_parser.add_argument("template", help="書き出し先のパス。")

    embed_parser = subparsers.add_parser("embed", help="テンプレートを書き戻す。")
    embed_parser.add_argument("gguf", help="書き換える対象のGGUFファイル。")
    embed_parser.add_argument("template", help="書き戻すテンプレートのパス。")

    args = parser.parse_args()
    if args.command == "extract":
        extract(args.gguf, args.template)
    else:
        embed(args.gguf, args.template)


if __name__ == "__main__":
    main()
