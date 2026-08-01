import logging
import os
import signal
import subprocess
import sys
from pathlib import Path
from typing import Any

import folder_paths
from comfy.model_management import throw_exception_if_processing_interrupted

logger = logging.getLogger(__name__)

# custom_nodes配下のsymlinkのままのパスを保つため実体解決はしない。
# resolve()するとこのノード自身のNix storeパスへ飛んでしまい、
# 隣のSeedVR2ディレクトリを辿れなくなる。
seedvr2_dir = Path(__file__).absolute().parent.parent / "ComfyUI-SeedVR2_VideoUpscaler"


class GetVideoSize:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, Any]:
        return {"required": {"video": ("VIDEO",)}}

    RETURN_TYPES = ("INT", "INT")
    RETURN_NAMES = ("width", "height")
    FUNCTION = "get_size"
    CATEGORY = "video"

    def get_size(self, video: Any) -> tuple[int, int]:
        return video.get_dimensions()


class SeedVR2StreamingVideoUpscaler:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, Any]:
        return {
            "required": {
                "video": ("VIDEO",),
                "dit": ("SEEDVR2_DIT",),
                "vae": ("SEEDVR2_VAE",),
                "seed": ("INT", {"default": 42, "min": 0, "max": 2**32 - 1}),
                "resolution": (
                    "INT",
                    {"default": 2160, "min": 16, "max": 16384, "step": 2},
                ),
                "max_resolution": (
                    "INT",
                    {"default": 3840, "min": 0, "max": 16384, "step": 2},
                ),
                "output_width": (
                    "INT",
                    {"default": 3840, "min": 2, "max": 16384, "step": 2},
                ),
                "output_height": (
                    "INT",
                    {"default": 2160, "min": 2, "max": 16384, "step": 2},
                ),
                "batch_size": (
                    "INT",
                    {"default": 5, "min": 1, "max": 16384, "step": 4},
                ),
                "uniform_batch_size": ("BOOLEAN", {"default": True}),
                "color_correction": (
                    ["lab", "wavelet", "wavelet_adaptive", "hsv", "adain", "none"],
                    {"default": "lab"},
                ),
                "temporal_overlap": (
                    "INT",
                    {"default": 3, "min": 0, "max": 16},
                ),
                "prepend_frames": (
                    "INT",
                    {"default": 0, "min": 0, "max": 32},
                ),
                "input_noise_scale": (
                    "FLOAT",
                    {"default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001},
                ),
                "latent_noise_scale": (
                    "FLOAT",
                    {"default": 0.0, "min": 0.0, "max": 1.0, "step": 0.001},
                ),
                "offload_device": (["none", "cpu", "cuda:0"], {"default": "cpu"}),
                "chunk_size": (
                    "INT",
                    {"default": 128, "min": 5, "max": 1000},
                ),
                "filename_prefix": ("STRING", {"default": "anime-video-upscale"}),
                "crf": ("INT", {"default": 1, "min": 0, "max": 51}),
                "lossless": ("BOOLEAN", {"default": True}),
                "enable_debug": ("BOOLEAN", {"default": False}),
            }
        }

    RETURN_TYPES = ()
    FUNCTION = "upscale"
    CATEGORY = "video"
    OUTPUT_NODE = True

    def upscale(
        self,
        video: Any,
        dit: dict[str, Any],
        vae: dict[str, Any],
        seed: int,
        resolution: int,
        max_resolution: int,
        output_width: int,
        output_height: int,
        batch_size: int,
        uniform_batch_size: bool,
        color_correction: str,
        temporal_overlap: int,
        prepend_frames: int,
        input_noise_scale: float,
        latent_noise_scale: float,
        offload_device: str,
        chunk_size: int,
        filename_prefix: str,
        crf: int,
        lossless: bool,
        enable_debug: bool,
    ) -> dict[str, Any]:
        source = video.get_stream_source()
        if not isinstance(source, (str, os.PathLike)):
            raise TypeError("SeedVR2 streaming requires a video backed by a file")

        # inference_cli.pyは`--vae_model`を持たずVAEはDEFAULT_VAE固定なので、
        # UIで他のVAEを選んでも反映されない。黙って無視せず失敗させる。
        cli_fixed_vae = "ema_vae_fp16.safetensors"
        if vae["model"] != cli_fixed_vae:
            raise ValueError(
                f"SeedVR2 CLI always uses VAE {cli_fixed_vae}, got {vae['model']}"
            )
        # CLIは両モデル共通の単一推論デバイスを`--cuda_device`で受け取る。
        if dit["device"] != vae["device"]:
            raise ValueError(
                "SeedVR2 CLI uses a single inference device for both models, "
                f"got DiT={dit['device']} and VAE={vae['device']}"
            )
        cuda_device = dit["device"].removeprefix("cuda:")
        if not cuda_device.isdigit():
            raise ValueError(
                f"SeedVR2 CLI only supports cuda devices, got {dit['device']}"
            )
        # torch compile設定はCLIへ引き渡していない。
        if (
            dit["torch_compile_args"] is not None
            or vae["torch_compile_args"] is not None
        ):
            raise ValueError(
                "torch compile settings are not forwarded to the SeedVR2 CLI"
            )

        output_dir, filename, counter, subfolder, _ = folder_paths.get_save_image_path(
            filename_prefix,
            folder_paths.get_output_directory(),
            output_width,
            output_height,
        )
        output_name = f"{filename}_{counter:05}_.mp4"
        output_path = Path(output_dir) / output_name
        partial_path = Path(output_dir) / f"{filename}_{counter:05}_.partial.mp4"
        model_dir = os.path.join(folder_paths.models_dir, "SEEDVR2")

        command = [
            sys.executable,
            str(seedvr2_dir / "inference_cli.py"),
            "--output",
            os.fspath(partial_path),
            "--output_format",
            "mp4",
            "--video_backend",
            "ffmpeg",
            "--10bit",
            "--crf",
            str(crf),
            "--output_width",
            str(output_width),
            "--output_height",
            str(output_height),
            "--model_dir",
            model_dir,
            "--dit_model",
            dit["model"],
            "--cuda_device",
            cuda_device,
            "--resolution",
            str(resolution),
            "--max_resolution",
            str(max_resolution),
            "--batch_size",
            str(batch_size),
            "--seed",
            str(seed),
            "--chunk_size",
            str(chunk_size),
            "--temporal_overlap",
            str(temporal_overlap),
            "--prepend_frames",
            str(prepend_frames),
            "--color_correction",
            color_correction,
            "--input_noise_scale",
            str(input_noise_scale),
            "--latent_noise_scale",
            str(latent_noise_scale),
            "--dit_offload_device",
            dit["offload_device"],
            "--vae_offload_device",
            vae["offload_device"],
            "--tensor_offload_device",
            offload_device,
            "--blocks_to_swap",
            str(dit["blocks_to_swap"]),
            "--attention_mode",
            dit["attention_mode"],
            "--vae_encode_tile_size",
            str(vae["encode_tile_size"]),
            "--vae_encode_tile_overlap",
            str(vae["encode_tile_overlap"]),
            "--vae_decode_tile_size",
            str(vae["decode_tile_size"]),
            "--vae_decode_tile_overlap",
            str(vae["decode_tile_overlap"]),
            "--tile_debug",
            str(vae["tile_debug"]),
        ]
        enabled_flags = {
            "--lossless": lossless,
            "--uniform_batch_size": uniform_batch_size,
            "--swap_io_components": dit["swap_io_components"],
            "--cache_dit": dit["cache_model"],
            "--vae_encode_tiled": vae["encode_tiled"],
            "--vae_decode_tiled": vae["decode_tiled"],
            "--cache_vae": vae["cache_model"],
            "--debug": enable_debug,
        }
        command.extend(flag for flag, enabled in enabled_flags.items() if enabled)
        # 入力パスは`--`の後の位置引数として渡し、
        # HTTPアップロード由来の`-`で始まるファイル名が、
        # argparseにオプションとして解釈されるのを防ぐ(CWE-88)。
        command.extend(["--", os.fspath(source)])

        logger.info("Running SeedVR2 streaming upscale: %s", " ".join(command))
        process = subprocess.Popen(command, start_new_session=True)
        try:
            # wait(timeout=1)は終了した瞬間に返るので、
            # poll()とsleep(1)の組と違い正常終了時に最大1秒待たされない。
            # 割り込みの確認間隔は従来どおり1秒のまま。
            while True:
                try:
                    process.wait(timeout=1)
                    break
                except subprocess.TimeoutExpired:
                    throw_exception_if_processing_interrupted()
            if process.returncode != 0:
                raise subprocess.CalledProcessError(process.returncode, command)
            if not partial_path.is_file() or partial_path.stat().st_size == 0:
                raise RuntimeError("SeedVR2 did not produce a video")
            os.replace(partial_path, output_path)
        except BaseException:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError as error:
                    logger.info(
                        "SeedVR2 process already exited before SIGTERM: %s", error
                    )
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError as error:
                        logger.info(
                            "SeedVR2 process already exited before SIGKILL: %s", error
                        )
                    process.wait()
            partial_path.unlink(missing_ok=True)
            raise

        return {
            "ui": {
                "gifs": [
                    {
                        "filename": output_name,
                        "subfolder": subfolder,
                        "type": "output",
                        "format": "video/mp4",
                    }
                ]
            }
        }


NODE_CLASS_MAPPINGS: dict[str, type[Any]] = {
    "GetVideoSize": GetVideoSize,
    "SeedVR2StreamingVideoUpscaler": SeedVR2StreamingVideoUpscaler,
}
NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {
    "GetVideoSize": "Get Video Size",
    "SeedVR2StreamingVideoUpscaler": "SeedVR2 Streaming Video Upscaler",
}
