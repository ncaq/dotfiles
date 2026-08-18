"""Qwen-Image-Editへ渡す画像の寸法を決めるモジュール。

ComfyUIやtorchに触れないので、
`custom-node/tests/`のpytestからそのままimportできる。

なぜ専用の寸法計算が要るのかは、
`custom-node/qwen-edit-scale/__init__.py`の冒頭に書いてある。
このファイル自体はsymlinkで複数のノードのディレクトリに置かれるので、
参照先はパスまで書いておく。
"""

import math

# `TextEncodeQwenImageEditPlus`が参照latentを作る時に合わせる総画素。
# ComfyUIの`comfy_extras/nodes_qwen.py`の`total = int(1024 * 1024)`と同じ。
VAE_IMAGE_PIXELS = 1024 * 1024

# 同じく参照latentの寸法を丸める単位。
# VAEが8分の1へ縮めるので、latentの1画素が元画像の8画素にあたる。
LATENT_DOWNSCALE = 8

# DiTがlatentをpatch化する単位。
# `comfy/ldm/qwen_image/model.py`の`patch_size`が2で、
# latentの寸法が奇数だと`pad_to_patch_size`のcircular paddingで、
# 反対側の端の内容が1行または1列だけ回り込む。
PATCH_SIZE = 2

# 元画像に要求する寸法の倍数。
# これを満たせばlatentの寸法が偶数になり、patch化のpaddingが起きない。
SIZE_MULTIPLE = LATENT_DOWNSCALE * PATCH_SIZE

# 極端なアスペクト比は学習時の分布から外れるので、この範囲へ丸める。
MAX_ASPECT_RATIO = 3.0

# 候補を探す幅。
# `SIZE_MULTIPLE`単位で理想の寸法の周囲をこの数だけ試す。
# 0.25から4.0までのアスペクト比をこの範囲で網羅できる。
# 広げても結果が変わらないことは、
# `tests/test_qwen_edit_size.py`が探索ステップを4倍にして確かめている。
WIDTH_SEARCH_STEPS = 12
HEIGHT_SEARCH_STEPS = 6


def reference_size(width: int, height: int) -> tuple[int, int]:
    """`TextEncodeQwenImageEditPlus`が参照latent用に計算する寸法を再現する。

    ComfyUIの実装をそのまま写したもので、
    総画素`VAE_IMAGE_PIXELS`へアスペクト比を保って合わせ、
    `LATENT_DOWNSCALE`の倍数へ丸める。
    """
    scale = math.sqrt(VAE_IMAGE_PIXELS / (width * height))
    return (
        round(width * scale / LATENT_DOWNSCALE) * LATENT_DOWNSCALE,
        round(height * scale / LATENT_DOWNSCALE) * LATENT_DOWNSCALE,
    )


def is_stable(width: int, height: int) -> bool:
    """エンコード側の再計算を受けても寸法が変わらないかを返す。

    これが成り立つ寸法で入力すれば、
    サンプリングするlatentと参照latentが同じ寸法になり、
    参照画像が出力の格子とずれない。
    """
    return reference_size(width, height) == (width, height)


def target_size(width: int, height: int) -> tuple[int, int]:
    """入力画像の寸法から、モデルへ渡すべき寸法を返す。

    以下を全て満たす寸法のうち、
    求めるアスペクト比に最も近く、総画素が`VAE_IMAGE_PIXELS`に近いものを選ぶ。

    - 幅も高さも`SIZE_MULTIPLE`の倍数
    - `is_stable`が成り立つ

    求める比は元の比を`MAX_ASPECT_RATIO`の範囲へ丸めたものである。
    3対1より極端な入力では返り値の比が元と一致しないので、
    呼び出し側が中央cropで吸収する時に画像の端が落ちる。

    総画素も`VAE_IMAGE_PIXELS`へ合わせるので、
    約1MPより小さい画像は拡大される。

    候補が見つからない場合は例外にする。
    黙って条件を緩めると、
    このノードを置いた意味が無い寸法が混ざっても気付けない。
    """
    if width <= 0 or height <= 0:
        raise ValueError(f"Image dimensions {width}x{height} must be positive")

    aspect_ratio = min(max(width / height, 1 / MAX_ASPECT_RATIO), MAX_ASPECT_RATIO)
    ideal_width = math.sqrt(VAE_IMAGE_PIXELS * aspect_ratio)

    best_score = None
    best_size = None
    base_width = round(ideal_width / SIZE_MULTIPLE)
    for width_offset in range(-WIDTH_SEARCH_STEPS, WIDTH_SEARCH_STEPS + 1):
        candidate_width = (base_width + width_offset) * SIZE_MULTIPLE
        if candidate_width < SIZE_MULTIPLE:
            continue
        base_height = round(candidate_width / aspect_ratio / SIZE_MULTIPLE)
        for height_offset in range(-HEIGHT_SEARCH_STEPS, HEIGHT_SEARCH_STEPS + 1):
            candidate_height = (base_height + height_offset) * SIZE_MULTIPLE
            if candidate_height < SIZE_MULTIPLE:
                continue
            if not is_stable(candidate_width, candidate_height):
                continue
            # アスペクト比の誤差は比の対数で測る。
            # 縦長と横長で同じずれが同じ大きさになる。
            score = (
                abs(math.log((candidate_width / candidate_height) / aspect_ratio)),
                abs(candidate_width * candidate_height - VAE_IMAGE_PIXELS),
            )
            if best_score is None or score < best_score:
                best_score = score
                best_size = (candidate_width, candidate_height)

    if best_size is None:
        raise ValueError(
            f"No stable size found for {width}x{height} (aspect ratio {aspect_ratio})"
        )
    return best_size
