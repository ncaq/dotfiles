# 画像の幅と高さを指定した倍数へ切り下げるComfyUIノード。
# Animaなどlatent寸法に制約があるモデルへ画像を渡す前に使う。
# リサイズによる歪みやpadding追加を避けるため、中央から最大multiple - 1pxだけcropする。
from typing import Any

import torch


class AlignImageSize:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, Any]:
        return {
            "required": {
                "image": ("IMAGE",),
                "multiple": ("INT", {"default": 16, "min": 1, "max": 256, "step": 1}),
            }
        }

    RETURN_TYPES: tuple[str] = ("IMAGE",)
    FUNCTION: str = "align"
    CATEGORY: str = "image/transform"

    def align(self, image: torch.Tensor, multiple: int) -> tuple[torch.Tensor]:
        height = image.shape[1]
        width = image.shape[2]
        if height < multiple or width < multiple:
            raise ValueError(
                f"Image dimensions {width}x{height} must be at least {multiple} pixels"
            )
        target_height = height // multiple * multiple
        target_width = width // multiple * multiple
        top = (height - target_height) // 2
        left = (width - target_width) // 2
        return (image[:, top : top + target_height, left : left + target_width, :],)


class AlignImageDimensions:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, Any]:
        return {
            "required": {
                "width": ("INT", {"default": 1024, "min": 16, "max": 16384, "step": 8}),
                "height": (
                    "INT",
                    {"default": 1024, "min": 16, "max": 16384, "step": 8},
                ),
                "multiple": ("INT", {"default": 16, "min": 1, "max": 256, "step": 1}),
            }
        }

    RETURN_TYPES: tuple[str, str] = ("INT", "INT")
    RETURN_NAMES: tuple[str, str] = ("width", "height")
    FUNCTION: str = "align"
    CATEGORY: str = "image/transform"

    def align(self, width: int, height: int, multiple: int) -> tuple[int, int]:
        if width < multiple or height < multiple:
            raise ValueError(
                f"Image dimensions {width}x{height} must be at least {multiple} pixels"
            )
        return (width // multiple * multiple, height // multiple * multiple)


NODE_CLASS_MAPPINGS: dict[str, type[AlignImageSize] | type[AlignImageDimensions]] = {
    "AlignImageSize": AlignImageSize,
    "AlignImageDimensions": AlignImageDimensions,
}
NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {
    "AlignImageSize": "Align Image Size",
    "AlignImageDimensions": "Align Image Dimensions",
}
