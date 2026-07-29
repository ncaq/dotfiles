import json
import logging
import math
import os
from fractions import Fraction
from typing import Any

import av
import torch

import folder_paths
from server import PromptServer

logger = logging.getLogger(__name__)


def warn_video_only(error: object) -> None:
    detail = f"音声を保存できなかったため、映像のみ保存します: {error}"
    logger.warning(detail)
    try:
        PromptServer.instance.send_sync(
            "save-svt-av1.warning",
            {
                "summary": "音声を保存できませんでした",
                "detail": detail,
                "life": 24 * 60 * 60 * 1000,
            },
            PromptServer.instance.client_id,
        )
    except Exception as notification_error:
        logger.warning(
            "Failed to show audio warning in ComfyUI: %s", notification_error
        )


class SaveSvtAv1:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, Any]:
        return {
            "required": {
                "images": ("IMAGE",),
                "fps": ("FLOAT", {"default": 24.0, "min": 0.01, "max": 1000.0}),
                "filename_prefix": ("STRING", {"default": "ComfyUI"}),
                "crf": ("INT", {"default": 1, "min": 0, "max": 63}),
                "preset": ("INT", {"default": 4, "min": 0, "max": 10}),
            },
            "optional": {"audio": ("AUDIO",)},
            "hidden": {"prompt": "PROMPT", "extra_pnginfo": "EXTRA_PNGINFO"},
        }

    RETURN_TYPES = ()
    FUNCTION = "save"
    CATEGORY = "video"
    OUTPUT_NODE = True

    def save(
        self,
        images: torch.Tensor,
        fps: float,
        filename_prefix: str,
        crf: int,
        preset: int,
        audio: dict[str, Any] | None = None,
        prompt: dict[str, Any] | None = None,
        extra_pnginfo: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        height, width = images.shape[1:3]
        if width % 2 != 0 or height % 2 != 0:
            raise ValueError(f"SVT-AV1 requires even dimensions, got {width}x{height}")

        output_dir, filename, counter, subfolder, _ = folder_paths.get_save_image_path(
            filename_prefix,
            folder_paths.get_output_directory(),
            width,
            height,
        )
        output_name = f"{filename}_{counter:05}_.mkv"
        output_path = os.path.join(output_dir, output_name)
        partial_path = os.path.join(output_dir, f"{filename}_{counter:05}_.partial.mkv")
        frame_rate = Fraction(fps).limit_denominator(1001)

        with av.open(partial_path, mode="w") as container:
            if prompt is not None:
                container.metadata["prompt"] = json.dumps(prompt)
            if extra_pnginfo is not None:
                container.metadata["extra_pnginfo"] = json.dumps(extra_pnginfo)

            video_stream = container.add_stream("libsvtav1", rate=frame_rate)
            video_stream.width = width
            video_stream.height = height
            video_stream.pix_fmt = "yuv420p10le"
            video_stream.bit_rate = 0
            video_stream.options = {"crf": str(crf), "preset": str(preset)}

            audio_stream = None
            audio_frames: list[av.AudioFrame] = []
            if audio is not None:
                try:
                    sample_rate = int(audio["sample_rate"])
                    waveform = audio["waveform"][0]
                    sample_limit = math.ceil(
                        (sample_rate / frame_rate) * images.shape[0]
                    )
                    waveform = waveform[:, :sample_limit].float()
                    layouts = {
                        1: "mono",
                        2: "stereo",
                        3: "3.0",
                        4: "quad",
                        5: "5.0",
                        6: "5.1",
                        7: "6.1",
                        8: "7.1",
                    }
                    if waveform.shape[0] != 0:
                        layout = layouts.get(waveform.shape[0], "mono")
                        if waveform.shape[0] not in layouts:
                            waveform = waveform.mean(dim=0, keepdim=True)

                        def convert_audio(
                            source: torch.Tensor, target_layout: str
                        ) -> list[av.AudioFrame]:
                            source_array = (
                                source.transpose(0, 1)
                                .contiguous()
                                .view(1, -1)
                                .cpu()
                                .numpy()
                            )
                            source_frame = av.AudioFrame.from_ndarray(
                                source_array, format="flt", layout=target_layout
                            )
                            source_frame.sample_rate = sample_rate
                            resampler = av.AudioResampler(
                                format="s32p", layout=target_layout, rate=sample_rate
                            )
                            return resampler.resample(
                                source_frame
                            ) + resampler.resample(None)

                        try:
                            audio_frames = convert_audio(waveform, layout)
                        except Exception as error:
                            logger.warning(
                                "Failed to preserve audio channels; retrying as mono: %s",
                                error,
                            )
                            layout = "mono"
                            audio_frames = convert_audio(
                                waveform.mean(dim=0, keepdim=True), layout
                            )

                        if audio_frames:
                            audio_stream = container.add_stream(
                                "flac", rate=sample_rate, layout=layout
                            )
                    else:
                        warn_video_only("音声のチャンネル数が0です")
                except Exception as error:
                    warn_video_only(error)
                    audio_stream = None
                    audio_frames = []

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
                for packet in video_stream.encode(frame):
                    container.mux(packet)
            container.mux(video_stream.encode())

            if audio_stream is not None:
                try:
                    audio_pts = 0
                    for frame in audio_frames:
                        frame.pts = audio_pts
                        frame.time_base = Fraction(1, frame.sample_rate)
                        audio_pts += frame.samples
                        container.mux(audio_stream.encode(frame))
                    container.mux(audio_stream.encode(None))
                except Exception as error:
                    warn_video_only(error)

        os.replace(partial_path, output_path)

        return {
            "ui": {
                "gifs": [
                    {
                        "filename": output_name,
                        "subfolder": subfolder,
                        "type": "output",
                        "format": "video/mkv",
                    }
                ]
            }
        }


NODE_CLASS_MAPPINGS: dict[str, type[SaveSvtAv1]] = {"SaveSvtAv1": SaveSvtAv1}
NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {"SaveSvtAv1": "Save SVT-AV1 10-bit"}
WEB_DIRECTORY = "./web"
