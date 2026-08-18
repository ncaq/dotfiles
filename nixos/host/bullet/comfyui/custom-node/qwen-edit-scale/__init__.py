# Qwen-Image-Editへ入力する画像を、参照latentとずれない寸法へ揃えるノード。
#
# 公式テンプレートはFluxKontextImageScaleでリサイズしているが、
# あれはFlux Kontextの17個の解像度バケットへ吸着させるノードで、
# Qwen-Image-Editの都合は見ていない。
#
# `TextEncodeQwenImageEditPlus`はvaeを繋ぐと、
# 渡された画像を改めて総画素1024*1024へ縮めてから参照latentを作る。
# バケットの総画素はちょうど1024*1024ではないので、
# ここで寸法がわずかに変わることがある。
# 例えば1328x800は1320x792になる。
#
# こうなると2つの問題が同時に起きる。
#
# 1つはサンプリングするlatentとのずれである。
# KSamplerが埋めるのは1328x800のlatentなのに、
# 参照は0.6%小さい1320x792を引き伸ばさずそのまま同じ格子へ載せるので、
# 参照画像が出力に対して端へ行くほどずれる。
#
# もう1つがpatch化のpaddingである。
# 1320/8=165と792/8=99はどちらも奇数なので、
# DiTのpatch_size=2で割り切れず`pad_to_patch_size`が1行1列足す。
# このpaddingのmodeはcircularなので、
# 足される内容は反対側の端、つまり画像の上端と左端になる。
# 結果として出力の下端8pxが画像上端のコピーで埋まる。
# 実際にbulletの1328x800の出力では、
# 下端8pxの色が最下部の風景ではなく上端の色と一致していた。
# 1392x752のように寸法が変わらないバケットではこの帯は出ない。
#
# そこでこのノードは、
# エンコード側の再計算を受けても寸法が変わらず、
# かつ幅も高さも16の倍数(latentが偶数)になる寸法を選んでリサイズする。
# 条件を満たす寸法は元のアスペクト比の近くに必ず見つかるので、
# バケットへの吸着より歪みも小さい。
#
# 画像は任意入力にしてある。
# LoadImageOptionalが(none)で出すNoneをそのまま素通しできるので、
# 任意の参照画像の経路にも同じように挟める。
#
# 寸法の計算は共有モジュールの`qwen_edit_size.py`へ分けてある。
# ComfyUIもtorchも要らないので`custom-node/tests/`から検査でき、
# 同じQwen-Image-Editを内部で走らせるanime-video-quickからも使う。
#
# ComfyUI本体は型注釈をほとんど持たないので、
# `comfy.utils.common_upscale`の戻り値の型が決まらず、
# torchの`movedim`のスタブにも不明な部分がある。
# strictのUnknown系はこれらに触れる式を全て挙げてしまう。
# 上流に型が付くまではこのファイルでだけ落とす。
# pyright: reportUnknownMemberType=none
# pyright: reportUnknownVariableType=none

import torch

import comfy.utils

from .qwen_edit_size import target_size


class QwenImageEditScale:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, object]:
        return {
            "required": {},
            "optional": {"image": ("IMAGE",)},
        }

    RETURN_TYPES: tuple[str] = ("IMAGE",)
    FUNCTION: str = "scale"
    CATEGORY: str = "image/transform"

    def scale(self, image: torch.Tensor | None = None) -> tuple[torch.Tensor | None]:
        if image is None:
            return (None,)
        width, height = target_size(image.shape[2], image.shape[1])
        # 本家のFluxKontextImageScaleと同じく、
        # lanczosで縮めてアスペクト比の差は中央cropで吸収する。
        # アルファは落とす。
        # この先のVAEもVLもRGBしか見ないので、持ち回っても使われない。
        scaled = comfy.utils.common_upscale(
            image[..., :3].movedim(-1, 1), width, height, "lanczos", "center"
        ).movedim(1, -1)
        return (scaled,)


NODE_CLASS_MAPPINGS: dict[str, type[QwenImageEditScale]] = {
    "QwenImageEditScale": QwenImageEditScale,
}

NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {
    "QwenImageEditScale": "Qwen Image Edit Scale",
}
