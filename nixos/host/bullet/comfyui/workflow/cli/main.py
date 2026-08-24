"""ComfyUIのワークフローを名前付きのオプションで投げるコマンド。

`local.comfyui.workflows`が宣言しているワークフローごとに、
`comfy-<ワークフロー名>`という名前で呼べるようにするための本体である。

    comfy-anima-standard --positive-prompt "1girl, blue hair" --seed 314

やっていることは3つしかない。

- UI形式のワークフローをAPI形式へ直す(`convert.py`)
- App Modeの入力定義をコマンドラインのオプションにする(`params.py`)
- `{a|b|c}`から1つ選ぶ(`dynamic.py`)
- `POST /prompt`へ投げて、結果のファイルが出るまで待つ

# なぜ変換を実行時にやるか

UI形式からAPI形式への変換にはノード定義が要る。
定義を返す`/object_info`は動いているComfyUIにしか聞けないので、
Nixの評価時に取るとimport from derivationになり、
カスタムノードの構成にも依存する。

このコマンドはそもそもComfyUIへ投げるためのもので、
投げられない状況では何もできない。
評価時に困る問い合わせも、実行時なら前提が揃っている。

そのかわり`--help`だけでもComfyUIを起こす。
ソケットアクティベーションで寝ている時は、
オプションの一覧を見るためだけにコンテナが起きることになる。
オプションの型や選択肢はノード定義から取っているので、
起こさずに正しい一覧を出す方法が無い。

# 何を環境変数から取るか

接続先とワークフローの出力ディレクトリを取る。
どちらもNixの側が知っていて、
`cli.nix`がラッパーへ埋め込む。

`http://`をこのファイルで固定するのは、
`idle-free-memory/main.py`と同じ理由による。
"""

import argparse
import http.client
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import convert
import dynamic
import nodedef
from convert import Prompt
from jsonutil import as_array, as_object, as_text
from nodedef import Widget
from params import Parameter, apply, apply_seed, parameters

# HTTPの待ち時間の上限。
# ソケットアクティベーションで寝ている時は、
# 最初の1本がComfyUIの起動を丸ごと待つことになる。
# CUDAの初期化とカスタムノードの読み込みで数十秒かかる。
REQUEST_TIMEOUT_SECONDS = 300

# 結果を確かめる間隔。
# 生成は速いもので10秒ほどなので、
# 終わってから気付くまでの遅れが目立たない程度にする。
POLL_INTERVAL_SECONDS = 1.0

# 全体のオプションが使う名前。
# パラメータ側には譲らせる。
RESERVED_FLAGS = frozenset(
    {
        "help",
        "seed",
        "repeat",
        "dry-run",
        "no-wait",
    }
)


def get_json(authority: str, path: str) -> object:
    """GETしてJSONを読む。"""
    with urllib.request.urlopen(
        f"http://{authority}{path}", timeout=REQUEST_TIMEOUT_SECONDS
    ) as response:
        body: bytes = response.read()
    parsed: object = json.loads(body)
    return parsed


def fetch_node_defs(authority: str) -> dict[str, nodedef.NodeDef]:
    """ノード定義を取りに行く。

    最初にComfyUIへ触るのがここなので、
    接続できない場合の説明もここで出す。
    tracebackを見せても、
    分かるのは`urlopen`が失敗したことだけで、
    どこへ繋ごうとしたのかが出ない。
    """
    try:
        return nodedef.parse(get_json(authority, "/object_info"))
    except (OSError, ValueError, http.client.HTTPException) as error:
        raise SystemExit(
            f"ComfyUIのノード定義を{authority}から取得できませんでした: {error}"
        ) from error


def post_prompt(authority: str, payload: dict[str, object]) -> object:
    """`POST /prompt`へ投げて応答を読む。

    検証で弾かれた場合は本文にどのノードの何が悪いのかが入っている。
    `HTTPError`のまま投げると本文が出ないので、ここで取り出す。
    """
    try:
        with urllib.request.urlopen(
            urllib.request.Request(
                f"http://{authority}/prompt",
                data=json.dumps(payload).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            ),
            timeout=REQUEST_TIMEOUT_SECONDS,
        ) as response:
            body: bytes = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"ComfyUIが受け付けませんでした: {detail}") from error
    except (OSError, http.client.HTTPException) as error:
        raise SystemExit(f"ComfyUIへ投入できませんでした: {error}") from error
    parsed: object = json.loads(body)
    return parsed


def parse_value(widget: Widget, text: str) -> object:
    """コマンドラインの文字列をウィジェットの型へ直す。"""
    if widget.kind == "INT":
        return int(text)
    if widget.kind == "FLOAT":
        return float(text)
    if widget.kind == "BOOLEAN":
        if text.lower() in ("true", "1", "yes", "on"):
            return True
        if text.lower() in ("false", "0", "no", "off"):
            return False
        raise ValueError(f"真偽値として読めません: {text}")
    if widget.kind == "COMBO" and widget.choices and text not in widget.choices:
        raise ValueError(f"選べるのは{', '.join(widget.choices)}のいずれかです")
    return text


def build_parser(name: str, params: list[Parameter]) -> argparse.ArgumentParser:
    """ワークフロー1つ分のコマンドラインを組み立てる。"""
    parser = argparse.ArgumentParser(
        prog=f"comfy-{name}",
        description=(
            f"ComfyUIのワークフロー{name}を実行します。"
            "プロンプトには`{a|b|c}`と書けます。投げるたびに1つが選ばれます。"
        ),
        # 既定値は`--help`の中に自分で書く。
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--seed",
        type=int,
        help="乱数のseed。省略すると毎回振り直します。"
        "UIでfixedにしてあるものには配りません。",
    )
    parser.add_argument(
        "--repeat",
        type=int,
        default=1,
        help="同じ設定で投げる回数。seedは1ずつずらします。",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="投げずにAPI形式のプロンプトを表示します。",
    )
    parser.add_argument(
        "--no-wait",
        action="store_true",
        help="投入したら結果を待たずに終わります。",
    )
    for parameter in params:
        described = parameter.description or parameter.widget.name
        choices = (
            f" 選択肢: {', '.join(parameter.widget.choices)}"
            if parameter.widget.kind == "COMBO" and parameter.widget.choices
            else ""
        )
        parser.add_argument(
            f"--{parameter.name}",
            dest=f"param_{parameter.name.replace('-', '_')}",
            metavar=parameter.widget.kind,
            help=f"{described} (既定: {parameter.default!r}){choices}",
        )
    return parser


def collect_outputs(entry: object) -> list[str]:
    """履歴1件から、保存されたファイルのパスを集める。

    保存ノードの種類ごとに`images`や`gifs`のようにキーが違うので、
    キーを決め打ちせずに`filename`を持つものを拾う。
    入力として置き直しただけのものは`type`が`output`にならないので外す。
    """
    files: list[str] = []
    outputs = as_object(as_object(entry).get("outputs"))
    for node_output in outputs.values():
        for values in as_object(node_output).values():
            for raw in as_array(values):
                item = as_object(raw)
                filename = as_text(item.get("filename"))
                if not filename or as_text(item.get("type")) != "output":
                    continue
                subfolder = as_text(item.get("subfolder"))
                files.append(f"{subfolder}/{filename}" if subfolder else filename)
    return files


def wait_for(authority: str, prompt_id: str) -> list[str]:
    """履歴に現れるまで待って、保存されたファイルのパスを返す。"""
    while True:
        time.sleep(POLL_INTERVAL_SECONDS)
        try:
            history = as_object(get_json(authority, f"/history/{prompt_id}"))
        except (OSError, ValueError, http.client.HTTPException) as error:
            # 生成中のComfyUIは重い。
            # 応答が返らなかったくらいで諦めずに次の周回で聞き直す。
            print(f"状態を取得できませんでした: {error}", file=sys.stderr)
            continue
        entry = history.get(prompt_id)
        if entry is not None:
            return collect_outputs(entry)


def run(
    authority: str,
    output_dir: str,
    prompt: Prompt,
    seed: int,
    wait: bool,
    dynamic_sources: dict[tuple[str, str], str],
) -> None:
    """1回分を投げて、待つなら結果を出す。"""
    applied = apply_seed(prompt, seed)
    if applied:
        print(f"seed {seed} を {', '.join(applied)} へ配りました")
    # 選び直すのは投げる直前である。
    # `--repeat`で複数回投げる時に、
    # 毎回違う組み合わせを引かせるためにここへ置く。
    for target, text in dynamic.expand_into(prompt, dynamic_sources, seed).items():
        print(f"{target}: {text}")
    response = post_prompt(authority, {"prompt": prompt.api()})
    prompt_id = as_text(as_object(response).get("prompt_id"))
    if not prompt_id:
        raise SystemExit(f"prompt_idが返りませんでした: {response!r}")
    print(f"投入しました: {prompt_id}")
    if not wait:
        return
    for file in wait_for(authority, prompt_id):
        print(str(Path(output_dir) / file) if output_dir else file)


def main() -> None:
    # 名前とパスを別々に受け取る。
    # パスはstoreの中にあり、
    # ファイル名の頭にハッシュが付くのでそこからは名前を取れない。
    # 使い方を誤った時のメッセージに出るのは名前の方である。
    if len(sys.argv) < 3:
        raise SystemExit("引数はワークフローの名前とJSONのパスです")
    name = sys.argv[1]
    workflow_path = Path(sys.argv[2])
    authority = os.environ.get("COMFYUI_AUTHORITY", "127.0.0.1:8188")
    output_dir = os.environ.get("COMFYUI_OUTPUT_DIR", "")

    workflow: object = json.loads(workflow_path.read_text(encoding="utf-8"))
    node_defs = fetch_node_defs(authority)
    prompt = convert.to_api(workflow, node_defs)
    problems = convert.missing_required(prompt, node_defs)
    if problems:
        raise SystemExit(
            "ワークフローの変換結果に必須入力の欠落があります:\n" + "\n".join(problems)
        )
    params = parameters(workflow, prompt, node_defs, reserved=RESERVED_FLAGS)

    parser = build_parser(name, params)
    args = parser.parse_args(sys.argv[3:])

    for parameter in params:
        given: object = getattr(args, f"param_{parameter.name.replace('-', '_')}")
        if given is None:
            continue
        try:
            apply(prompt, parameter, parse_value(parameter.widget, str(given)))
        except ValueError as error:
            parser.error(f"--{parameter.name}: {error}")

    seed: int = (
        args.seed if args.seed is not None else secrets.randbelow(0xFFFF_FFFF_FFFF)
    )
    repeat: int = args.repeat
    # パラメータを反映した後で集める。
    # `--positive-prompt`で選択肢を渡す使い方が主なので、
    # ワークフローに書かれている値だけを見ても足りない。
    dynamic_sources = dynamic.sources(prompt, node_defs)
    if args.dry_run:
        dynamic.expand_into(prompt, dynamic_sources, seed)
        json.dump(prompt.api(), sys.stdout, ensure_ascii=False, indent=1)
        print()
        return
    for index in range(repeat):
        run(
            authority,
            output_dir,
            prompt,
            seed=seed + index,
            wait=not args.no_wait,
            dynamic_sources=dynamic_sources,
        )


if __name__ == "__main__":
    main()
