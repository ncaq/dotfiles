# 保存したPNGを、画素を変えずに小さくし直すモジュール。
#
# ComfyUIのPNG保存はPillowの`compress_level=4`で、
# 生成の待ち時間を延ばさないよう圧縮を軽く済ませている。
# 画像は消さずに増えていく一方なので、
# 生成時間に比べれば無視できる時間で1割縮むなら縮めておきたい。
#
# oxipngは行フィルタの選び直しと再圧縮を試すだけで画素は変えないため、
# 差し替えても画像の中身は同じになる。
# 既定ではチャンクも落とさないので、
# ComfyUIがtEXtへ書くpromptとworkflowも残り、
# 画像をComfyUIへ投げ込んでワークフローを復元する使い方も壊れない。
#
# 保存が終わった後にバックグラウンドのスレッドでoxipngを回す。
# 保存自体は既に成功しているので、
# 縮めるのに失敗してもワークフローは成功のままにしてログだけ残す。
# 書き込み途中のファイルを掴まれないよう、
# `--out`で`.partial`付きの名前へ書いてから`os.replace`で差し替える。
#
# 動画の配布用エンコードと違って直列化はしない。
# oxipngが1枚に使うCPUは`-o max`でも5コア程度で、
# 生成中に遊んでいる32スレッドのごく一部で済むため、
# 何枚か並んでも取り合いにはならない。
#
# 各カスタムノードのパッケージへsymlinkJoinで同じファイルを配り、
# `from .optimize_png import start_optimize_png`と相対importで使う。
import logging
import os
import subprocess
import threading
from pathlib import Path

logger = logging.getLogger(__name__)

# oxipngの最適化レベル。
# ComfyUIが出力した4枚(1392x752から1536x1536、合計9.76MiB)での実測。
#
#   -o 2(既定):              11.66%減    4.8秒
#   -o 5:                    12.30%減    8.2秒
#   -o max:                  12.34%減   12.0秒
#   -o max --fast --zopfli:  12.63%減  151.3秒
#   -o max --zopfli:         12.63%減  163.9秒
#
# 削減率はレベルを上げてもほとんど伸びず、12%台で頭打ちになる。
# zopfliは`-o max`から更に0.3ポイント縮むだけで13倍の時間がかかり、
# `--fast`の有無でも結果が変わらなかったので使わない。
# それでも`-o max`を選ぶのは、
# 1枚3秒程度と生成にかかる数十秒から数分に対しては誤差だからで、
# 頭打ちの範囲で一番縮む設定を取っておく。
#
# なお`--interlace`の既定は`off`なので明示していない。
optimize_level = "max"


def start_optimize_png(path: Path) -> None:
    """`path`のPNGを可逆に縮めて置き換える作業を開始する。"""
    threading.Thread(
        target=optimize_png,
        args=(path,),
        name=f"optimize-png-{path.name}",
        daemon=True,
    ).start()


def optimize_png(path: Path) -> None:
    # niceはLinuxではスレッド単位の属性で、子プロセスは生成元スレッドの値を継ぐ。
    # このスレッドだけを譲る側へ回して、oxipngが生成のCPUを奪わないようにする。
    os.nice(19)
    partial = path.with_suffix(".partial.png")
    command = [
        "oxipng",
        "--opt",
        optimize_level,
        # 差し替えは自分で行うので、oxipngには別名で書かせる。
        "--out",
        os.fspath(partial),
        # 生成日時としての意味があるので、縮めた時刻で更新日時を上書きしない。
        "--preserve",
        os.fspath(path),
    ]
    try:
        before = path.stat().st_size
        # 成功時に出る統計は自前のログと重複するので捨てる。
        # `--quiet`だと失敗の理由まで消えてしまうため、
        # 黙らせるのではなく出力を受け取っておく。
        subprocess.run(
            command,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        after = partial.stat().st_size
        os.replace(partial, path)
        logger.info("Optimized PNG: %s: %d -> %d bytes", path, before, after)
    # 元のPNGは既に保存されているので、ここで失敗しても生成はやり直させない。
    except subprocess.CalledProcessError as error:
        logger.warning(
            "Failed to optimize PNG: %s: %s: %s", path, error, error.stderr.strip()
        )
    except Exception as error:
        logger.warning("Failed to optimize PNG: %s: %s", path, error)
    finally:
        # 失敗した時に書きかけを残さない。成功していれば既に消えている。
        partial.unlink(missing_ok=True)
