"""Qwen-Image-Edit向けの寸法計算の単体テスト。

このノードの存在意義は、
選んだ寸法が`TextEncodeQwenImageEditPlus`の再計算を受けても変わらないことと、
latentの寸法が偶数になることの2点だけである。
どちらも満たさないと出力の下端や右端に反対側の端が回り込むが、
生成してみるまで気付けない。
成り立つアスペクト比の範囲ごと、ここで固定する。
"""

import math

import pytest
import qwen_edit_size


def aspect_ratios() -> list[float]:
    """検査するアスペクト比。極端な比まで含めて広く取る。"""
    return [0.25 + 0.01 * step for step in range(376)]


@pytest.mark.parametrize("aspect_ratio", aspect_ratios())
def test_size_is_stable_and_even(aspect_ratio: float) -> None:
    """どのアスペクト比でも、再計算で変わらず16の倍数の寸法が見つかる。"""
    height = 2048
    width = max(round(height * aspect_ratio), 1)
    target_width, target_height = qwen_edit_size.target_size(width, height)

    assert qwen_edit_size.is_stable(target_width, target_height)
    assert target_width % qwen_edit_size.SIZE_MULTIPLE == 0
    assert target_height % qwen_edit_size.SIZE_MULTIPLE == 0


@pytest.mark.parametrize("aspect_ratio", aspect_ratios())
def test_size_keeps_aspect_ratio_and_pixels(aspect_ratio: float) -> None:
    """アスペクト比と総画素が元の要求から大きく外れない。"""
    height = 2048
    width = max(round(height * aspect_ratio), 1)
    target_width, target_height = qwen_edit_size.target_size(width, height)

    clamped = min(
        max(aspect_ratio, 1 / qwen_edit_size.MAX_ASPECT_RATIO),
        qwen_edit_size.MAX_ASPECT_RATIO,
    )
    error = abs(math.log((target_width / target_height) / clamped))
    assert error < math.log(1.05)
    assert 0.9 < (target_width * target_height) / qwen_edit_size.VAE_IMAGE_PIXELS < 1.1


def test_reference_size_matches_comfyui() -> None:
    """参照latentの寸法の再現が、実際にずれる例で期待通りになる。

    1328x800はFluxKontextImageScaleのバケットの1つで、
    エンコード側の再計算で1320x792へ動いてしまう組み合わせである。
    1320も792も16で割り切れないため、patch化のpaddingまで起きる。
    この計算がずれるとノードの前提が崩れるので、実測値で固定する。
    """
    assert qwen_edit_size.reference_size(1328, 800) == (1320, 792)
    assert not qwen_edit_size.is_stable(1328, 800)
    # 同じバケット表でも寸法が変わらないものはそのまま通る。
    assert qwen_edit_size.is_stable(1392, 752)


def test_replaces_unstable_bucket() -> None:
    """ずれるバケットの入力には、近いアスペクト比の安定した寸法を返す。"""
    target_width, target_height = qwen_edit_size.target_size(1328, 800)

    assert qwen_edit_size.is_stable(target_width, target_height)
    assert (target_width, target_height) != (1328, 800)


@pytest.mark.parametrize(("width", "height"), [(0, 100), (100, 0), (-1, 100)])
def test_rejects_empty_image(width: int, height: int) -> None:
    """面積の無い画像は、どこがおかしいのか分かる形で拒否する。"""
    with pytest.raises(ValueError, match="must be positive"):
        qwen_edit_size.target_size(width, height)
