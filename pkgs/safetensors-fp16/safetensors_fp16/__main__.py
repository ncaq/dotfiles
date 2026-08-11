"""safetensorsのF32テンソルだけをF16へ変換するCLIのエントリポイント。"""

import argparse
import sys

from .convert import convert
from .verify import verify


def main() -> int:
    parser = argparse.ArgumentParser(
        description="safetensorsのF32テンソルだけをF16へ変換する。"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    convert_parser = subparsers.add_parser("convert", help="変換してdstへ書き出す。")
    convert_parser.add_argument("src", help="変換元のsafetensorsファイル。")
    convert_parser.add_argument("dst", help="書き出し先のパス。")
    convert_parser.add_argument(
        "--allow-overflow",
        action="store_true",
        help="fp16の範囲を超える重みがinfになることを許容する。",
    )

    verify_parser = subparsers.add_parser(
        "verify", help="変換結果をsrcと突き合わせる。"
    )
    verify_parser.add_argument("src", help="変換元のsafetensorsファイル。")
    verify_parser.add_argument("dst", help="検証するsafetensorsファイル。")

    args = parser.parse_args()
    if args.command == "convert":
        convert(args.src, args.dst, allow_overflow=args.allow_overflow)
    else:
        verify(args.src, args.dst)
    return 0


if __name__ == "__main__":
    sys.exit(main())
