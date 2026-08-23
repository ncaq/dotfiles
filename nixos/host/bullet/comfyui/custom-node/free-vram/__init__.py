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
# あちらが降ろした重みは、その後の生成でどのみち載り直す。
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
# ComfyUI本体は型注釈をほとんど持たないが、
# このファイルが`comfy`へ触れるのは戻り値を使わない2つの呼び出しだけなので、
# 他の自作ノードが置いている`# pyright:`によるUnknown系の抑制は要らない。

import sys
import traceback

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
            try:
                # `unload_all_models`だけでも他のプロセスから見た空きは増える。
                # bulletでAnimaを載せた直後に`/free`で測ると、
                # 5788MiBがこれだけで1506MiBまで落ちた。
                # `RewriteEditPrompt`が`unload_all_models`しか呼ばないのは、
                # そのため片手落ちではない。
                #
                # それでも`soft_empty_cache`を続けて呼ぶのは、
                # 同じ測定で1506MiBが1358MiBまで下がったからである。
                # 差は148MiBしかないが、
                # 次に載るOllamaの汎用モデルは32GiBに対して28.8GiBあり、
                # 全層をGPUへ載せた状態でも空きは2GiB程度しか残らない。
                # 返せるものは返しておく方が、部分オフロードへ落ちる余地が減る。
                comfy.model_management.unload_all_models()
                comfy.model_management.soft_empty_cache(force=True)
                # 降ろしたことをログに残す。
                # 次の生成が遅い時に、
                # 載せ直しが理由なのかどうかをジャーナルから判断できるようにする。
                print("[FreeVram] モデルをVRAMから降ろしました", file=sys.stderr)
            except Exception:
                # 空け損ねても画像は返す。
                # このノードは保存ノードの手前に挟まるので、
                # ここで例外を投げると数分かけた生成が保存されないまま失われる。
                # VRAMの解放は生成結果に対して副次的な処理でしかなく、
                # 失敗しても次にOllamaがOOMになるだけで、生成物を捨てる理由にはならない。
                # 副次的な処理の失敗で本筋を止めない方針は`RewriteEditPrompt`と同じである。
                #
                # 例外の文字列だけでは足りないのでtracebackごと残す。
                # `CUDA error`系はメッセージを持つが、
                # 上流のAPIが変わった時の`AttributeError`のように、
                # どこで何を呼んで失敗したのかが要る場面ほど文字列が短くなる。
                print(
                    f"[FreeVram] VRAMの解放に失敗しました:\n{traceback.format_exc()}",
                    file=sys.stderr,
                )
        return (image,)


NODE_CLASS_MAPPINGS: dict[str, type[FreeVram]] = {
    "FreeVram": FreeVram,
}

NODE_DISPLAY_NAME_MAPPINGS: dict[str, str] = {
    "FreeVram": "Free VRAM",
}
