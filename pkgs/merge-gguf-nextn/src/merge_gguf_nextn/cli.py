"""`merge-gguf-nextn`コマンドの入口。"""

import argparse
import logging
import sys
from pathlib import Path

from merge_gguf_nextn.merge import MergeError, merge


def main() -> None:
    parser = argparse.ArgumentParser(
        description="GGUFの本体へ、別ファイルで配られたMTPのNextN層を足します。",
    )
    parser.add_argument("main", type=Path, help="NextN層を持たない本体のGGUF")
    parser.add_argument("draft", type=Path, help="NextN層を持つドラフトヘッドのGGUF")
    parser.add_argument("output", type=Path, help="書き出すGGUF")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    try:
        merge(args.main, args.draft, args.output)
    except MergeError as e:
        print(f"merge-gguf-nextn: {e}", file=sys.stderr)
        sys.exit(1)
