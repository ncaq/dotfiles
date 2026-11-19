# ComfyUIが読み込む入口。
#
# ComfyUIは`custom_nodes/`直下のディレクトリを1つのパッケージとして読み、
# ここの`NODE_CLASS_MAPPINGS`に載っているクラスをノードとして登録する。
# ノードはモジュールごとに書いて、ここで1つにまとめる。
#
# ノードごとにディレクトリを分けないのは、
# 翻訳や配布用エンコードのような複数のノードが使うモジュールを、
# 普通の相対importで共有するためである。
from . import (
    anime_video_quick,
    free_vram,
    load_image_optional,
    rewrite_edit_prompt,
    save_svt_av1,
    seedvr2_streaming,
    translate_text,
)

# ノードは提供せず、読み込んだ時に本体のSaveImageを包む副作用だけを持つ。
from . import optimize_saved_png as optimize_saved_png

NODE_CLASS_MAPPINGS: dict[str, type] = {
    **anime_video_quick.NODE_CLASS_MAPPINGS,
    **free_vram.NODE_CLASS_MAPPINGS,
    **load_image_optional.NODE_CLASS_MAPPINGS,
    **rewrite_edit_prompt.NODE_CLASS_MAPPINGS,
    **save_svt_av1.NODE_CLASS_MAPPINGS,
    **seedvr2_streaming.NODE_CLASS_MAPPINGS,
    **translate_text.NODE_CLASS_MAPPINGS,
}
NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {
    **anime_video_quick.NODE_DISPLAY_NAME_MAPPINGS,
    **free_vram.NODE_DISPLAY_NAME_MAPPINGS,
    **load_image_optional.NODE_DISPLAY_NAME_MAPPINGS,
    **rewrite_edit_prompt.NODE_DISPLAY_NAME_MAPPINGS,
    **save_svt_av1.NODE_DISPLAY_NAME_MAPPINGS,
    **seedvr2_streaming.NODE_DISPLAY_NAME_MAPPINGS,
    **translate_text.NODE_DISPLAY_NAME_MAPPINGS,
}
# `save_svt_av1.py`が出す警告をトーストで表示するフロントエンド拡張。
WEB_DIRECTORY = "./web"
