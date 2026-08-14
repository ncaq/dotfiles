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
for directory in [custom_node, custom_node / "anime-video-quick"]:
    sys.path.insert(0, str(directory))
