"""GGUFのチャットテンプレートの出し入れの単体テスト。

このスクリプトは22GB級のGGUFをin-placeで書き換える。
オフセットの計算を1バイトでも間違えると、
テンプレートではなく隣のメタデータやテンソルを壊すが、
壊れたGGUFはロードするまで、
場合によってはそのテンソルを通る推論をするまで表面化しない。
実物で試すには重すぎるので、
同じ構造を持つ小さなGGUFを組み立てて検査する。

特に確かめるのは、
可変長の値(文字列と文字列の配列)を挟んでも目的のキーへ辿り着けることと、
書き戻した後にテンプレート以外の全てのバイトが元のままであることの2点である。
"""

import struct
from pathlib import Path

import patch_gguf_chat_template as target
import pytest

# テンプレートの前後に置くメタデータ。
# 可変長の値を前に置いて、読み飛ばしの誤りがオフセットに出るようにする。
# 後ろにも置いて、書き戻しが範囲を越えていないことを見られるようにする。
ARCHITECTURE = b"qwen3"
TOKENS = [b"a", b"bb", b"ccc"]
TENSOR_DATA = b"tensor-data-placeholder"


def encode_string(value: bytes) -> bytes:
    """長さプレフィックス付きの文字列を組み立てる。"""
    return struct.pack("<Q", len(value)) + value


def encode_kv(key: str, value_type: int, payload: bytes) -> bytes:
    """メタデータの1項目を組み立てる。"""
    return encode_string(key.encode()) + struct.pack("<I", value_type) + payload


def build_gguf(template: bytes | None, version: int = target.GGUF_VERSION) -> bytes:
    """テンプレートを含む最小のGGUFを組み立てる。

    `template`が`None`ならチャットテンプレートの項目自体を持たない。
    """
    entries = [
        encode_kv(
            "general.architecture", target.TYPE_STRING, encode_string(ARCHITECTURE)
        ),
        # uint32の固定長。
        encode_kv("general.quantization_version", 4, struct.pack("<I", 2)),
        # 文字列の配列。要素ごとに長さが違うので1つずつ読み飛ばす経路を通る。
        encode_kv(
            "tokenizer.ggml.tokens",
            target.TYPE_ARRAY,
            struct.pack("<IQ", target.TYPE_STRING, len(TOKENS))
            + b"".join(encode_string(token) for token in TOKENS),
        ),
        # int32の配列。まとめて読み飛ばす経路を通る。
        encode_kv(
            "tokenizer.ggml.token_type",
            target.TYPE_ARRAY,
            struct.pack("<IQ", 5, len(TOKENS)) + struct.pack("<iii", 1, 1, 1),
        ),
    ]
    if template is not None:
        entries.append(
            encode_kv(
                "tokenizer.chat_template", target.TYPE_STRING, encode_string(template)
            )
        )
    # テンプレートより後ろにも項目を置く。
    entries.append(encode_kv("general.file_type", 4, struct.pack("<I", 18)))

    header = (
        target.GGUF_MAGIC
        + struct.pack("<I", version)
        + struct.pack("<QQ", 0, len(entries))
    )
    return header + b"".join(entries) + TENSOR_DATA


def write_gguf(tmp_path: Path, content: bytes) -> Path:
    """GGUFを一時ディレクトリへ置いてパスを返す。"""
    path = tmp_path / "model.gguf"
    path.write_bytes(content)
    return path


def test_extract_reads_the_template(tmp_path: Path) -> None:
    """可変長の値を挟んでもテンプレートをそのまま取り出せる。"""
    template = b"{{- 'hello' }}"
    gguf = write_gguf(tmp_path, build_gguf(template))
    extracted = tmp_path / "chat_template.jinja"

    target.extract(str(gguf), str(extracted))

    assert extracted.read_bytes() == template


def test_embed_keeps_every_other_byte(tmp_path: Path) -> None:
    """書き戻してもテンプレート以外のバイトは1つも変わらない。"""
    template = b"{{- raise_exception('nope') }}"
    original = build_gguf(template)
    gguf = write_gguf(tmp_path, original)
    patched = tmp_path / "chat_template.jinja"
    patched.write_bytes(b"{{- 'ok' }}")

    target.embed(str(gguf), str(patched))

    result = gguf.read_bytes()
    assert len(result) == len(original)
    offset = original.index(template)
    assert result[:offset] == original[:offset]
    assert result[offset + len(template) :] == original[offset + len(template) :]


def test_embed_pads_the_shortened_template(tmp_path: Path) -> None:
    """縮んだ分はJinjaのコメントで埋められ、取り出すと現れる。"""
    template = b"{{- raise_exception('nope') }}"
    gguf = write_gguf(tmp_path, build_gguf(template))
    patched = tmp_path / "chat_template.jinja"
    patched.write_bytes(b"{{- 'ok' }}")

    target.embed(str(gguf), str(patched))
    target.extract(str(gguf), str(patched))

    # 30バイトの枠へ11バイトを書き、残る19バイトのうち4バイトをコメントの記号が使う。
    assert patched.read_bytes() == b"{{- 'ok' }}{#" + b" " * 15 + b"#}"


def test_embed_rejects_a_longer_template(tmp_path: Path) -> None:
    """伸びる置換は埋めようがないので書き込まずに落ちる。"""
    template = b"{{- 'short' }}"
    original = build_gguf(template)
    gguf = write_gguf(tmp_path, original)
    patched = tmp_path / "chat_template.jinja"
    patched.write_bytes(template + b"!")

    with pytest.raises(SystemExit):
        target.embed(str(gguf), str(patched))

    assert gguf.read_bytes() == original


@pytest.mark.parametrize("padding", [1, 2, 3])
def test_pad_to_length_rejects_a_half_comment(padding: int) -> None:
    """Jinjaのコメントに満たない端数は埋められない。"""
    template = b"{{- 'ok' }}"
    with pytest.raises(SystemExit):
        target.pad_to_length(template, len(template) + padding)


def test_pad_to_length_fills_the_smallest_comment() -> None:
    """4バイトちょうどなら空のコメントで埋まる。"""
    template = b"{{- 'ok' }}"
    assert target.pad_to_length(template, len(template) + 4) == template + b"{##}"


def test_pad_to_length_keeps_the_exact_length() -> None:
    """長さが一致していれば何も足さない。"""
    template = b"{{- 'ok' }}"
    assert target.pad_to_length(template, len(template)) == template


def test_missing_template_is_reported(tmp_path: Path) -> None:
    """チャットテンプレートを持たないGGUFは、黙って素通りせずに落ちる。"""
    gguf = write_gguf(tmp_path, build_gguf(None))
    with pytest.raises(SystemExit):
        target.extract(str(gguf), str(tmp_path / "chat_template.jinja"))


def test_unexpected_version_is_reported(tmp_path: Path) -> None:
    """v2以前は読み取りのフォーマットから違うので受け付けない。"""
    gguf = write_gguf(tmp_path, build_gguf(b"{{- 'ok' }}", version=2))
    with pytest.raises(SystemExit):
        target.extract(str(gguf), str(tmp_path / "chat_template.jinja"))


def test_non_gguf_is_reported(tmp_path: Path) -> None:
    """マジックナンバーが違うファイルは読まない。"""
    gguf = write_gguf(tmp_path, b"NOTGGUF" + build_gguf(b"{{- 'ok' }}"))
    with pytest.raises(SystemExit):
        target.extract(str(gguf), str(tmp_path / "chat_template.jinja"))
