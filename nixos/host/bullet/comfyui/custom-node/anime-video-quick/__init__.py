import hashlib
import json
import math
import os
import re
import subprocess
import traceback
from datetime import datetime
from fractions import Fraction
from pathlib import Path
from typing import Any, NotRequired, TypedDict, cast

import av
import comfy.model_management
import comfy.utils
import folder_paths
import node_helpers
import nodes
import numpy as np
import requests
import torch
from comfy_extras.nodes_model_advanced import ModelSamplingSD3
from PIL import Image

from .optimize_png import start_optimize_png
from .share_encode import start_share_encode


anime_style_prefix = "Anime style, 2D cel animation, flat colors."
# 拡張子にロスレスかどうかとコーデック名も含めて、
# メタデータを確認しなくてもファイル名だけで中身が分かるようにする。
# 区間も結合後も10-bit SVT-AV1 losslessのWebMで書き出す。
video_suffix = ".lossless.av1.webm"
wan_frame_count = 81
wan_fps = 16.0
wan_temporal_compression = 4
negative_prompt = (
    "色调艳丽，过曝，静态，细节模糊不清，字幕，风格，作品，画作，画面，静止，"
    "整体发灰，最差质量，低质量，JPEG压缩残留，丑陋的，残缺的，多余的手指，"
    "画得不好的手部，画得不好的脸部，畸形的，毁容的，形态畸形的肢体，手指融合，"
    "静止不动的画面，杂乱的背景，三条腿，背景人很多，倒着走，写实风格，照片级，"
    "3D渲染，真人"
)


class Segment(TypedDict):
    scene: int
    prompt: str


class TranslatedSegment(Segment):
    english: str


class Manifest(TypedDict):
    """job IDごとに出力ディレクトリへ置く進捗の記録。

    中断したジョブを同じjob IDで再開する時にどこまで終わっているかを見る。
    キーが揃っていないと再開の判定を誤るので、
    どのキーがいつ現れるのかを型に出しておく。
    """

    # 生成条件。異なる条件で同じjob IDを使い回していないかの照合に使う。
    # キーを走査して比較するので、TypedDictにはせず素の辞書にする。
    identity: dict[str, object]
    segments: list[TranslatedSegment]
    status: str
    # ここから下は処理が進むにつれて現れる。
    completed_keyframes: NotRequired[int]
    completed_segments: NotRequired[int]
    video: NotRequired[str]
    error: NotRequired[str]


def split_prompts(text: str) -> list[Segment]:
    scene = 0
    segments: list[Segment] = []
    for line in text.splitlines():
        prompt = line.strip()
        if prompt:
            segments.append({"scene": scene, "prompt": prompt})
        elif segments and segments[-1]["scene"] == scene:
            scene += 1
    if not segments:
        raise ValueError("少なくとも1行の動画指示が必要です")
    return segments


def translate(text: str) -> str:
    try:
        response = requests.get(
            "https://translate.googleapis.com/translate_a/single",
            params={
                "client": "gtx",
                "sl": "auto",
                "tl": "en",
                "dt": "t",
                "q": text,
            },
            timeout=10,
        )
        response.raise_for_status()
        payload = response.json()
        if (
            not isinstance(payload, list)
            or not payload
            or not isinstance(payload[0], list)
        ):
            raise ValueError("Google Translate returned an invalid response")
        # `isinstance`だけでは要素の型が不明なままになり、
        # 取り出した先を型検査が見てくれないので`object`へ寄せる。
        texts: list[str] = []
        for segment in cast(list[object], payload[0]):
            if not isinstance(segment, list):
                continue
            items = cast(list[object], segment)
            if items and isinstance(items[0], str):
                texts.append(items[0])
        translated = "".join(texts)
        if not translated:
            raise ValueError("Google Translate returned an empty translation")
        return translated
    except Exception:
        print("[anime-video-quick] translation failed, using original text")
        traceback.print_exc()
        return text


def image_hash(image: torch.Tensor) -> str:
    data = image.detach().clamp(0, 1).mul(255).round().to(torch.uint8).cpu().numpy()
    return hashlib.sha256(data.tobytes()).hexdigest()


def save_image(image: torch.Tensor, path: Path) -> None:
    array = (
        image[0, ..., :3]
        .detach()
        .clamp(0, 1)
        .mul(255)
        .round()
        .to(torch.uint8)
        .cpu()
        .numpy()
    )
    temporary = path.with_suffix(".partial.png")
    Image.fromarray(array, "RGB").save(temporary)
    os.replace(temporary, path)
    # キーフレームは配布物ではないが、
    # 縮めても画素は変わらないので動画の区間と違って除外する理由がない。
    start_optimize_png(path)


def load_image(path: Path) -> torch.Tensor:
    with Image.open(path) as source:
        array = torch.from_numpy(np.array(source.convert("RGB"))).float() / 255.0
    return array.unsqueeze(0)


def flatten_image_batch(images: torch.Tensor) -> torch.Tensor:
    if images.ndim == 5:
        return images.reshape(-1, *images.shape[-3:])
    if images.ndim != 4:
        raise ValueError(
            f"Expected a 4D or 5D image batch, got shape {tuple(images.shape)}"
        )
    return images


def scaled_image(image: torch.Tensor, megapixels: float, multiple: int) -> torch.Tensor:
    height, width = image.shape[1:3]
    scale = math.sqrt(megapixels * 1_000_000 / (width * height))
    target_width = max(multiple, math.floor(width * scale / multiple) * multiple)
    target_height = max(multiple, math.floor(height * scale / multiple) * multiple)
    return comfy.utils.common_upscale(
        image[..., :3].movedim(-1, 1),
        target_width,
        target_height,
        "lanczos",
        "disabled",
    ).movedim(1, -1)


def qwen_image_conditioning(
    vae: Any, image: torch.Tensor
) -> tuple[torch.Tensor, torch.Tensor]:
    samples = image.movedim(-1, 1)
    vision_scale = math.sqrt(384 * 384 / (samples.shape[3] * samples.shape[2]))
    vision_width = round(samples.shape[3] * vision_scale)
    vision_height = round(samples.shape[2] * vision_scale)
    vision_image = comfy.utils.common_upscale(
        samples, vision_width, vision_height, "area", "disabled"
    ).movedim(1, -1)

    latent_scale = math.sqrt(1024 * 1024 / (samples.shape[3] * samples.shape[2]))
    latent_width = round(samples.shape[3] * latent_scale / 8) * 8
    latent_height = round(samples.shape[2] * latent_scale / 8) * 8
    latent_image = comfy.utils.common_upscale(
        samples, latent_width, latent_height, "area", "disabled"
    ).movedim(1, -1)
    reference_latent = vae.encode(latent_image[..., :3])
    return vision_image, reference_latent


def qwen_conditioning(
    clip: Any,
    vision_image: torch.Tensor,
    reference_latent: torch.Tensor,
    prompt: str,
) -> Any:

    template = (
        "<|im_start|>system\nDescribe the key features of the input image "
        "(color, shape, size, texture, objects, background), then explain how the user's text "
        "instruction should alter or modify the image. Generate a new image that meets the "
        "user's requirements while maintaining consistency with the original input where "
        "appropriate.<|im_end|>\n<|im_start|>user\n{}<|im_end|>\n"
        "<|im_start|>assistant\n"
    )
    tokens = clip.tokenize(
        "Picture 1: <|vision_start|><|image_pad|><|vision_end|>" + prompt,
        images=[vision_image],
        llama_template=template,
    )
    conditioning = clip.encode_from_tokens_scheduled(tokens)
    return node_helpers.conditioning_set_values(
        conditioning, {"reference_latents": [reference_latent]}, append=True
    )


def generate_keyframe(
    model: Any,
    clip: Any,
    vae: Any,
    image: torch.Tensor,
    prompt: str,
    seed: int,
) -> torch.Tensor:
    source = scaled_image(image, 1.0, 8)
    vision_image, reference_latent = qwen_image_conditioning(vae, source)
    positive = qwen_conditioning(clip, vision_image, reference_latent, prompt)
    negative = qwen_conditioning(clip, vision_image, reference_latent, "")
    latent = {"samples": vae.encode(source[..., :3])}
    sampled = nodes.common_ksampler(
        model, seed, 40, 4.0, "euler", "simple", positive, negative, latent, denoise=1.0
    )[0]
    return flatten_image_batch(vae.decode(sampled["samples"]))[:1]


def wan_conditioning(
    positive: Any,
    negative: Any,
    vae: Any,
    start_image: torch.Tensor,
    end_image: torch.Tensor,
    width: int,
    height: int,
) -> tuple[Any, Any, dict[str, torch.Tensor]]:
    latent_frame_count = (wan_frame_count - 1) // wan_temporal_compression + 1
    latent = torch.zeros(
        [
            1,
            vae.latent_channels,
            latent_frame_count,
            height // vae.spacial_compression_encode(),
            width // vae.spacial_compression_encode(),
        ],
        device=comfy.model_management.intermediate_device(),
    )
    start = comfy.utils.common_upscale(
        start_image[..., :3].movedim(-1, 1), width, height, "bilinear", "center"
    ).movedim(1, -1)
    end = comfy.utils.common_upscale(
        end_image[..., :3].movedim(-1, 1), width, height, "bilinear", "center"
    ).movedim(1, -1)
    images = torch.full((wan_frame_count, height, width, 3), 0.5)
    images[: start.shape[0]] = start
    images[-end.shape[0] :] = end
    mask = torch.ones(
        (
            1,
            1,
            latent.shape[2] * wan_temporal_compression,
            latent.shape[-2],
            latent.shape[-1],
        )
    )
    # Wan VAEの先頭潜在フレームに対応する元動画の全フレームを条件付けする。
    mask[:, :, : start.shape[0] + wan_temporal_compression - 1] = 0.0
    mask[:, :, -end.shape[0] :] = 0.0
    encoded = vae.encode(images)
    mask = mask.view(
        1,
        mask.shape[2] // wan_temporal_compression,
        wan_temporal_compression,
        mask.shape[3],
        mask.shape[4],
    ).transpose(1, 2)
    values = {"concat_latent_image": encoded, "concat_mask": mask}
    return (
        node_helpers.conditioning_set_values(positive, values),
        node_helpers.conditioning_set_values(negative, values),
        {"samples": latent},
    )


def generate_segment(
    model_high: Any,
    model_low: Any,
    clip: Any,
    negative: Any,
    vae: Any,
    start_image: torch.Tensor,
    end_image: torch.Tensor,
    prompt: str,
    seed: int,
    width: int,
    height: int,
) -> torch.Tensor:
    positive = clip.encode_from_tokens_scheduled(
        clip.tokenize(f"{anime_style_prefix} {prompt}")
    )
    positive, negative, latent = wan_conditioning(
        positive, negative, vae, start_image, end_image, width, height
    )
    high = nodes.KSamplerAdvanced().sample(
        model_high,
        "enable",
        seed,
        4,
        1.0,
        "euler",
        "simple",
        positive,
        negative,
        latent,
        0,
        2,
        "enable",
    )[0]
    low = nodes.KSamplerAdvanced().sample(
        model_low,
        "disable",
        0,
        4,
        1.0,
        "euler",
        "simple",
        positive,
        negative,
        high,
        2,
        10000,
        "disable",
    )[0]
    return flatten_image_batch(vae.decode(low["samples"]))


def partial_video_path(path: Path) -> Path:
    """書き込み途中の動画パス。

    ffmpegがコンテナを拡張子から推定できるように、
    `.partial`は末尾ではなく`video_suffix`の手前へ入れる。
    """
    return path.with_name(
        f"{path.name.removesuffix(video_suffix)}.partial{video_suffix}"
    )


def save_video(images: torch.Tensor, path: Path) -> None:
    height, width = images.shape[1:3]
    temporary = partial_video_path(path)
    with av.open(temporary, mode="w") as container:
        stream = container.add_stream(
            "libsvtav1", rate=Fraction(wan_fps).limit_denominator(1001)
        )
        # PyAVの型スタブはコーデック名のLiteral一覧にlibsvtav1を持たないため、
        # 音声や字幕のストリームも含む共用体が返る扱いになる。
        # 実際には映像ストリームなので絞ってから属性を設定する。
        if not isinstance(stream, av.VideoStream):
            raise TypeError(f"libsvtav1 stream is not a video stream: {type(stream)}")
        stream.width = width
        stream.height = height
        stream.pix_fmt = "yuv420p10le"
        stream.bit_rate = 0
        stream.options = {"preset": "4", "svtav1-params": "lossless=1"}
        for image in images:
            rgb48 = (
                image[..., :3]
                .float()
                .mul(65535)
                .round()
                .clamp(0, 65535)
                .to(torch.uint16)
                .contiguous()
                .cpu()
                .numpy()
            )
            frame = av.VideoFrame.from_ndarray(rgb48, format="rgb48le")
            for packet in stream.encode(frame):
                container.mux(packet)
        container.mux(stream.encode())
    os.replace(temporary, path)


def concat_videos(paths: list[Path], output_path: Path) -> None:
    list_path = paths[0].parent / "concat.txt"
    temporary = partial_video_path(output_path)
    list_path.write_text(
        "".join(f"file '{path.name}'\n" for path in paths), encoding="utf-8"
    )
    try:
        subprocess.run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-f",
                "concat",
                "-i",
                str(list_path),
                "-c",
                "copy",
                "-y",
                str(temporary),
            ],
            check=True,
        )
        os.replace(temporary, output_path)
    finally:
        list_path.unlink(missing_ok=True)
        temporary.unlink(missing_ok=True)


def write_manifest(path: Path, manifest: Manifest) -> None:
    temporary = path.with_suffix(".partial.json")
    temporary.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    os.replace(temporary, path)


def sanitize_job_id(job_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", job_id.strip()).strip(".-")


def file_fingerprint(path: Path, base: Path) -> tuple[str, int]:
    # ファイルサイズは見ない。
    # キーフレームは保存後にoxipngが縮めるため、
    # 内容が同じままサイズだけ後から変わる。
    # oxipngへは`--preserve`を渡していて更新日時は動かないので、
    # 更新日時だけを見れば作り直しを検出できる。
    status = path.stat()
    return path.relative_to(base).as_posix(), status.st_mtime_ns


class AnimeVideoQuick:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, Any]:
        return {
            "required": {
                "image": ("IMAGE",),
                "prompts": (
                    "STRING",
                    {
                        "multiline": True,
                        "default": "キャラクターはゆっくり振り返る。\n\nカメラへ向かって穏やかに微笑む。",
                    },
                ),
                "qwen_model": ("MODEL",),
                "qwen_clip": ("CLIP",),
                "qwen_vae": ("VAE",),
                "wan_model_high": (folder_paths.get_filename_list("diffusion_models"),),
                "wan_model_low": (folder_paths.get_filename_list("diffusion_models"),),
                "wan_clip": (folder_paths.get_filename_list("text_encoders"),),
                "wan_vae": (folder_paths.get_filename_list("vae"),),
                "seed": ("INT", {"default": 0, "min": 0, "max": 0xFFFFFFFFFFFFFFFF}),
                "retry_seed_offset": (
                    "INT",
                    {"default": 0, "min": 0, "max": 0xFFFFFFFFFFFFFFFF},
                ),
                "job_id": ("STRING", {"default": ""}),
            }
        }

    RETURN_TYPES = ("STRING",)
    RETURN_NAMES = ("video_path",)
    FUNCTION = "generate"
    CATEGORY = "video"
    OUTPUT_NODE = True

    @classmethod
    def IS_CHANGED(cls, job_id: str, **kwargs: Any) -> object:
        safe_job_id = sanitize_job_id(job_id)
        if not safe_job_id:
            return float("NaN")
        output_dir = (
            Path(folder_paths.get_output_directory())
            / "anime-video-quick"
            / safe_job_id
        )
        filename_prefix = f"anime-video-quick-{safe_job_id}"
        manifest_path = output_dir / "manifest.json"
        if not manifest_path.exists():
            return float("NaN")
        manifest: Manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        segment_count = len(manifest["segments"])
        expected_paths = [
            output_dir / "keyframes" / f"{filename_prefix}-keyframe-000-start.png",
            *(
                output_dir / "keyframes" / f"{filename_prefix}-keyframe-{index:03}.png"
                for index in range(1, segment_count + 1)
            ),
            *(
                output_dir
                / "segments"
                / f"{filename_prefix}-segment-{index:03}{video_suffix}"
                for index in range(segment_count)
            ),
            output_dir / f"{filename_prefix}-final{video_suffix}",
        ]
        if any(not path.is_file() for path in expected_paths):
            return float("NaN")
        return tuple(file_fingerprint(path, output_dir) for path in expected_paths)

    def generate(
        self,
        image: torch.Tensor,
        prompts: str,
        qwen_model: Any,
        qwen_clip: Any,
        qwen_vae: Any,
        wan_model_high: str,
        wan_model_low: str,
        wan_clip: str,
        wan_vae: str,
        seed: int,
        retry_seed_offset: int,
        job_id: str,
    ) -> dict[str, Any]:
        segments = split_prompts(prompts)
        safe_job_id = sanitize_job_id(job_id)
        if not safe_job_id:
            safe_job_id = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
        relative_dir = Path("anime-video-quick") / safe_job_id
        output_dir = Path(folder_paths.get_output_directory()) / relative_dir
        keyframe_dir = output_dir / "keyframes"
        segment_dir = output_dir / "segments"
        filename_prefix = f"anime-video-quick-{safe_job_id}"
        keyframe_dir.mkdir(parents=True, exist_ok=True)
        segment_dir.mkdir(parents=True, exist_ok=True)
        manifest_path = output_dir / "manifest.json"

        identity: dict[str, object] = {
            "schema": 1,
            "prompts": prompts,
            "image_sha256": image_hash(image),
            "seed": seed,
            "wan_model_high": wan_model_high,
            "wan_model_low": wan_model_low,
            "wan_clip": wan_clip,
            "wan_vae": wan_vae,
        }
        manifest: Manifest
        translated_segments: list[TranslatedSegment]
        if manifest_path.exists():
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            previous_identity = manifest.get("identity", {})
            differing_identity_keys = [
                key
                for key, value in identity.items()
                if previous_identity.get(key) != value
            ]
            if differing_identity_keys:
                raise ValueError(
                    "同じjob IDに異なる生成条件が指定されています: "
                    + ", ".join(differing_identity_keys)
                )
            translated_segments = manifest["segments"]
        else:
            translated_segments = [
                TranslatedSegment(
                    scene=segment["scene"],
                    prompt=segment["prompt"],
                    english=translate(segment["prompt"]),
                )
                for segment in segments
            ]
            manifest = {
                "identity": identity,
                "segments": translated_segments,
                "status": "running",
            }
            write_manifest(manifest_path, manifest)

        try:
            start_path = keyframe_dir / f"{filename_prefix}-keyframe-000-start.png"
            if not start_path.exists():
                save_image(image, start_path)
            first_missing_keyframe = next(
                (
                    index
                    for index in range(1, len(translated_segments) + 1)
                    if not (
                        keyframe_dir / f"{filename_prefix}-keyframe-{index:03}.png"
                    ).exists()
                ),
                None,
            )
            if first_missing_keyframe is not None:
                first_affected_segment = first_missing_keyframe - 1
                for index in range(first_affected_segment, len(translated_segments)):
                    (
                        segment_dir
                        / f"{filename_prefix}-segment-{index:03}{video_suffix}"
                    ).unlink(missing_ok=True)

            if first_missing_keyframe is not None:
                previous_path = (
                    start_path
                    if first_missing_keyframe == 1
                    else keyframe_dir
                    / f"{filename_prefix}-keyframe-{first_missing_keyframe - 1:03}.png"
                )
                current = load_image(previous_path)
                for index in range(
                    first_missing_keyframe, len(translated_segments) + 1
                ):
                    segment = translated_segments[index - 1]
                    keyframe_path = (
                        keyframe_dir / f"{filename_prefix}-keyframe-{index:03}.png"
                    )
                    current = generate_keyframe(
                        qwen_model,
                        qwen_clip,
                        qwen_vae,
                        current,
                        segment["english"],
                        (seed + retry_seed_offset + index - 1) & 0xFFFFFFFFFFFFFFFF,
                    )
                    save_image(current, keyframe_path)
                    manifest["completed_keyframes"] = index
                    write_manifest(manifest_path, manifest)
                del current

            video_paths = [
                segment_dir / f"{filename_prefix}-segment-{index:03}{video_suffix}"
                for index in range(len(translated_segments))
            ]
            if any(not path.exists() for path in video_paths):
                comfy.model_management.unload_all_models()
                comfy.model_management.soft_empty_cache(force=True)

                loaded_wan_model_high = ModelSamplingSD3().patch(
                    nodes.UNETLoader().load_unet(wan_model_high, "default")[0], 5
                )[0]
                loaded_wan_model_low = ModelSamplingSD3().patch(
                    nodes.UNETLoader().load_unet(wan_model_low, "default")[0], 5
                )[0]
                loaded_wan_clip = nodes.CLIPLoader().load_clip(
                    wan_clip, "wan", "default"
                )[0]
                loaded_wan_vae = nodes.VAELoader().load_vae(wan_vae)[0]
                wan_negative = loaded_wan_clip.encode_from_tokens_scheduled(
                    loaded_wan_clip.tokenize(negative_prompt)
                )
                wan_start = scaled_image(load_image(start_path), 0.9, 16)
                wan_height, wan_width = wan_start.shape[1:3]

                for index, (segment, video_path) in enumerate(
                    zip(translated_segments, video_paths, strict=True)
                ):
                    if video_path.exists():
                        continue
                    start = load_image(
                        start_path
                        if index == 0
                        else keyframe_dir / f"{filename_prefix}-keyframe-{index:03}.png"
                    )
                    end = load_image(
                        keyframe_dir / f"{filename_prefix}-keyframe-{index + 1:03}.png"
                    )
                    frames = generate_segment(
                        loaded_wan_model_high,
                        loaded_wan_model_low,
                        loaded_wan_clip,
                        wan_negative,
                        loaded_wan_vae,
                        start,
                        end,
                        segment["english"],
                        (seed + retry_seed_offset + index) & 0xFFFFFFFFFFFFFFFF,
                        wan_width,
                        wan_height,
                    )
                    if index != 0:
                        # 直前区間の終了フレームと同じ先頭フレームを重複させない。
                        frames = frames[1:]
                    save_video(frames, video_path)
                    manifest["completed_segments"] = index + 1
                    write_manifest(manifest_path, manifest)
                    del start, end, frames
                    comfy.model_management.soft_empty_cache()

            final_name = f"{filename_prefix}-final{video_suffix}"
            final_path = output_dir / final_name
            if not final_path.exists() or any(
                final_path.stat().st_mtime_ns < path.stat().st_mtime_ns
                for path in video_paths
            ):
                concat_videos(video_paths, final_path)
            # 区間は途中経過で配布物ではないので、結合後の完成品だけ圧縮版を作る。
            start_share_encode(final_path, video_suffix)
            manifest["status"] = "completed"
            manifest["video"] = str(final_path)
            manifest.pop("error", None)
            write_manifest(manifest_path, manifest)
            return {
                "ui": {
                    "gifs": [
                        {
                            "filename": final_name,
                            "subfolder": relative_dir.as_posix(),
                            "type": "output",
                            "format": "video/webm",
                        }
                    ]
                },
                "result": (str(final_path),),
            }
        except Exception as error:
            manifest["status"] = "failed"
            manifest["error"] = f"{type(error).__name__}: {error}"
            write_manifest(manifest_path, manifest)
            raise


NODE_CLASS_MAPPINGS = {"AnimeVideoQuick": AnimeVideoQuick}
NODE_DISPLAY_NAME_MAPPINGS = {"AnimeVideoQuick": "Anime Video Quick"}
