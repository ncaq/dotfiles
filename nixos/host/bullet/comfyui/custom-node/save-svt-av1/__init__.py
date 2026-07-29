import json
import math
import os
from fractions import Fraction
from typing import Any

import av
import torch

import folder_paths


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
        frame_rate = Fraction(round(fps * 1000), 1000)

        with av.open(output_path, mode="w") as container:
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
                sample_rate = int(audio["sample_rate"])
                waveform = audio["waveform"][0]
                sample_limit = math.ceil((sample_rate / frame_rate) * images.shape[0])
                waveform = waveform[:, :sample_limit].float().cpu().contiguous().numpy()
                layout = {1: "mono", 2: "stereo", 6: "5.1"}.get(
                    waveform.shape[0], "stereo"
                )
                audio_stream = container.add_stream(
                    "flac", rate=sample_rate, layout=layout
                )
                audio_frame = av.AudioFrame.from_ndarray(
                    waveform, format="fltp", layout=layout
                )
                audio_frame.sample_rate = sample_rate
                resampler = av.AudioResampler(
                    format="s32p", layout=layout, rate=sample_rate
                )
                audio_frames = resampler.resample(audio_frame) + resampler.resample(
                    None
                )

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
                audio_pts = 0
                for frame in audio_frames:
                    frame.pts = audio_pts
                    frame.time_base = Fraction(1, frame.sample_rate)
                    audio_pts += frame.samples
                    container.mux(audio_stream.encode(frame))
                container.mux(audio_stream.encode(None))

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
