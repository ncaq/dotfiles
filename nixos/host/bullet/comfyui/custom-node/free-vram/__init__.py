# ワークフローの終わりでComfyUIが載せたままの重みをVRAMから降ろすノード。
#
# ComfyUIはsmart memoryで実行後もモデルをVRAMへ保持する。
# 同じモデルを連続で使う分には正しい挙動だが、
# bulletではOllamaが同じGPUを使う。
# 汎用モデルは32GiBのVRAMに対して28.8GiBあるので、
# ComfyUIが重みを掴んだままだとCUDAのOOMで載らない。
#
# ComfyUIのコンテナは`socket-activation.nix`のオンデマンド起動で上がるが、
# 一度起動すると手で止めるまで動き続ける。
# `lib/container-socket-activation.nix`がアイドル停止を持たないのは、
# 生成の途中で止める誤爆の方が困るという判断による。
# そのため「使い終わったら勝手に空く」ことは起こらない。
#
# `RewriteEditPrompt`の`free_comfyui_vram`はこの逆向きの経路で、
# あちらはリライトのためにOllamaを呼ぶ直前に降ろす。
# こちらは生成が終わった後に降ろして、次にOllamaを使う人のために空けておく。
#
# 降ろすかどうかはトグルにする。
# 連続生成では毎回の載せ直しが効いてくるので、
# ブラウザからComfyUIを直接使う場合は保持したままの方が速い。
# 生成のたびに人が戻ってこないOpen WebUI経由でだけ有効にする。
#
# IMAGEを素通しするのは、実行順を依存グラフで表すためである。
# ComfyUIは接続の順序でしか実行順を決められないので、
# 保存ノードの手前へ挟んで「生成が全て終わった後」を表現する。
# 降ろすのはモデルであって画像のテンソルではないので、
# 素通しした画像はこの後も保存できる。
#
# ComfyUI本体は型注釈をほとんど持たず、
# `comfy.model_management`に触れる式がstrictのUnknown系を全て挙げてしまう。
# 上流に型が付くまではこのファイルでだけ落とす。
# pyright: reportUnknownArgumentType=none
# pyright: reportUnknownMemberType=none
# pyright: reportUnknownVariableType=none

import sys

import comfy.model_management
import torch


class FreeVram:
    @classmethod
    def INPUT_TYPES(cls) -> dict[str, object]:
        return {
            "required": {
                "image": ("IMAGE",),
                # 既定は保持したままにする。
                # ブラウザから直接使う場合が既定で、
                # そちらでは降ろすと連続生成のたびに載せ直しになる。
                "enabled": ("BOOLEAN", {"default": False}),
            },
        }

    RETURN_TYPES: tuple[str] = ("IMAGE",)
    RETURN_NAMES: tuple[str] = ("image",)
    FUNCTION: str = "free"
    CATEGORY: str = "utils"

    def free(self, image: torch.Tensor, enabled: bool) -> tuple[torch.Tensor]:
        if enabled:
            # `unload_all_models`はComfyUIが管理する重みをGPUから外すだけで、
            # PyTorchのcaching allocatorが確保済みのブロックは抱えたままになる。
            # 他のプロセスから見た空きは`empty_cache`まで呼んで初めて増えるため、
            # OOMを避けるにはこの2つが揃っている必要がある。
            comfy.model_management.unload_all_models()
            comfy.model_management.soft_empty_cache(force=True)
            # 降ろしたことをログに残す。
            # 次の生成が遅い時に、
            # 載せ直しが理由なのかどうかをジャーナルから判断できるようにする。
            print("[FreeVram] モデルをVRAMから降ろしました", file=sys.stderr)
        return (image,)


NODE_CLASS_MAPPINGS: dict[str, type[FreeVram]] = {
    "FreeVram": FreeVram,
}

NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {
    "FreeVram": "Free VRAM",
}
