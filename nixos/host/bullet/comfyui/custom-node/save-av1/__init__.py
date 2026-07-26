import json
import os
from fractions import Fraction

import av
import torch
from typing_extensions import override

import folder_paths
from comfy.cli_args import args
from comfy_api.latest import ComfyExtension, io, ui


class SaveAv1Mp4(io.ComfyNode):
    @classmethod
    def define_schema(cls) -> io.Schema:
        return io.Schema(
            node_id="SaveAv1Mp4",
            display_name="Save AV1 MP4",
            category="video",
            inputs=[
                io.Image.Input("images"),
                io.String.Input("filename_prefix", default="video/ComfyUI"),
                io.Float.Input(
                    "fps", default=24.0, min=0.01, max=1000.0, step=0.01
                ),
                io.Float.Input("crf", default=32.0, min=1, max=63, step=1),
            ],
            hidden=[io.Hidden.prompt, io.Hidden.extra_pnginfo],
            is_output_node=True,
            outputs=[io.Image.Output(display_name="images")],
        )

    @classmethod
    def execute(
        cls,
        images: torch.Tensor,
        filename_prefix: str,
        fps: float,
        crf: float,
    ) -> io.NodeOutput:
        height, width = images.shape[1:3]
        if width % 2 != 0 or height % 2 != 0:
            raise ValueError("SVT-AV1 yuv420p10le requires even dimensions")

        output_folder, filename, counter, subfolder, _ = (
            folder_paths.get_save_image_path(
                filename_prefix,
                folder_paths.get_output_directory(),
                width,
                height,
            )
        )
        file = f"{filename}_{counter:05}_.mp4"

        with av.open(
            os.path.join(output_folder, file),
            mode="w",
            format="mp4",
            options={"movflags": "use_metadata_tags"},
        ) as container:
            if not args.disable_metadata:
                if cls.hidden.prompt is not None:
                    container.metadata["prompt"] = json.dumps(cls.hidden.prompt)
                if cls.hidden.extra_pnginfo is not None:
                    for key, value in cls.hidden.extra_pnginfo.items():
                        container.metadata[key] = json.dumps(value)

            stream = container.add_stream(
                "libsvtav1", rate=Fraction(round(fps * 1000), 1000)
            )
            stream.width = width
            stream.height = height
            stream.pix_fmt = "yuv420p10le"
            stream.bit_rate = 0
            stream.options = {"crf": str(round(crf)), "preset": "6"}

            for image in images:
                frame = av.VideoFrame.from_ndarray(
                    torch.clamp(image[..., :3] * 65535, min=0, max=65535)
                    .to(device=torch.device("cpu"), dtype=torch.uint16)
                    .numpy(),
                    format="rgb48le",
                )
                for packet in stream.encode(frame):
                    container.mux(packet)
            for packet in stream.encode():
                container.mux(packet)

        return io.NodeOutput(
            images,
            ui=ui.PreviewVideo(
                [ui.SavedResult(file, subfolder, io.FolderType.output)]
            ),
        )


class SaveAv1Extension(ComfyExtension):
    @override
    async def get_node_list(self) -> list[type[io.ComfyNode]]:
        return [SaveAv1Mp4]


async def comfy_entrypoint() -> SaveAv1Extension:
    return SaveAv1Extension()
