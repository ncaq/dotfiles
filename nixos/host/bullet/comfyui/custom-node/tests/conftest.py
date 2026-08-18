"""カスタムノードのモジュールをComfyUIなしでimportできるようにする。

ComfyUIは`custom_nodes/`直下の各ノードのディレクトリをパッケージとして読むので、
共有モジュールもノード内のモジュールも相対importで解決される。
テストからは同じ並びをsys.pathで再現して、素のモジュールとしてimportする。

ここに置けるのはComfyUI本体やtorchに触れないモジュールだけである。
ノードの`__init__.py`はそれらをimportするので、
テストしたい処理はそこから分けておく必要がある。
"""

import sys
from pathlib import Path

custom_node = Path(__file__).resolve().parent.parent
# 共有モジュールはノードのディレクトリにもsymlinkで置かれているので、
# ルートを先頭にして必ず実体の側へ解決させる。
# `checks.comfyui-custom-node-test`のfilesetはsymlinkを含まないため、
# ここでノード側が勝つとローカルとcheckでモジュールの同一性が食い違う。
# `insert(0)`は後から入れたものが前に来るので、この並びは逆順に書く。
for directory in [
    custom_node / "rewrite-edit-prompt",
    custom_node / "anime-video-quick",
    custom_node,
]:
    sys.path.insert(0, str(directory))
