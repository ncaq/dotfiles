"""`response`と`state`をテストからimportできるようにする。

`main.py`はスクリプトとして起動されるので、
Pythonが自分の置かれたディレクトリをsys.pathの先頭へ入れる。
その並びをここで再現して、実機と同じ名前で解決させる。
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
