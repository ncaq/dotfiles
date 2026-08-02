# 画像を選ばないことも許可するLoadImage。
# 選択肢の先頭に(none)を追加した以外は本家LoadImageと同じ。
# (none)のままなら出力はNoneになり、
# 接続先のoptional入力へは未接続と同じ扱いで渡る。
#
# WanFirstLastFrameToVideoのend_imageのような任意入力に対して、
# ノードのバイパス操作なしで、
# 「画像が指定してあれば有効、なければ無効」を実現するためのもの。
from typing import Any

import torch

import nodes

NONE_CHOICE = "(none)"


class LoadImageOptional(nodes.LoadImage):
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, Any]:
        types = super().INPUT_TYPES()
        files, config = types["required"]["image"]
        types["required"]["image"] = ([NONE_CHOICE] + files, config)
        return types

    FUNCTION: str = "load_image_optional"

    def load_image_optional(
        self, image: str
    ) -> tuple[torch.Tensor | None, torch.Tensor | None]:
        if image == NONE_CHOICE:
            return (None, None)
        return self.load_image(image)

    @classmethod
    def IS_CHANGED(cls, image: str) -> str:
        if image == NONE_CHOICE:
            return NONE_CHOICE
        return super().IS_CHANGED(image)

    @classmethod
    def VALIDATE_INPUTS(cls, image: str) -> bool | str:
        if image == NONE_CHOICE:
            return True
        return super().VALIDATE_INPUTS(image)


NODE_CLASS_MAPPINGS: dict[str, type[LoadImageOptional]] = {
    "LoadImageOptional": LoadImageOptional,
}

NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {
    "LoadImageOptional": "Load Image (Optional)",
}
