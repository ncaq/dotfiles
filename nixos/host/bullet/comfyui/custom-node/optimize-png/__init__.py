# ComfyUI標準のSaveImageが書き出したPNGを、保存後にoxipngで縮めるだけのカスタムノード。
#
# ノードは足さず、`save_images`を包む副作用だけを持つ。
# PNGを出す経路のほとんどは本体側のSaveImageなので、
# 自作ノードを増やしてもワークフローを書き換えなければ効果がない。
#
# 本体へパッチを当てる方法もあるが、
# 包むだけなら保存処理の中身が変わっても追随が要らず、
# 万一戻り値の形が変わってもPNGが縮まなくなるだけで生成には影響しない。
import logging
from pathlib import Path
from typing import Any

import nodes

from .optimize_png import start_optimize_png

logger = logging.getLogger(__name__)

original_save_images = nodes.SaveImage.save_images


def save_images(self: nodes.SaveImage, *args: Any, **kwargs: Any) -> dict[str, Any]:
    result = original_save_images(self, *args, **kwargs)
    # PreviewImageもSaveImageを継承していて、こちらは一時ディレクトリへ書く。
    # すぐ消える画像を縮めても仕方がないので、出力ディレクトリの分だけ扱う。
    if getattr(self, "type", None) != "output":
        return result
    try:
        for image in result["ui"]["images"]:
            start_optimize_png(
                Path(self.output_dir) / image["subfolder"] / image["filename"]
            )
    except Exception as error:
        # 保存自体は終わっているので、ここで失敗しても生成はやり直させない。
        logger.warning("Failed to start PNG optimization: %s", error)
    return result


setattr(save_images, "optimize_png_wrapped", True)

# ComfyUI-Managerによる再読み込みなどでこのモジュールが二度読まれると、
# 何もしなければ包んだ関数を更に包んで1枚のPNGへoxipngを二重に走らせてしまう。
# 目印を見て、既に包んであれば差し替えない。
if not getattr(nodes.SaveImage.save_images, "optimize_png_wrapped", False):
    nodes.SaveImage.save_images = save_images

# ノードを提供しないが、これがないとComfyUIが読み込み失敗として扱う。
NODE_CLASS_MAPPINGS: dict[str, type] = {}
