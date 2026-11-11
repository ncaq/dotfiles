"""`merge`を小さな合成のGGUFで検査する。"""

from pathlib import Path

import gguf
import numpy as np
import pytest

from merge_gguf_nextn.merge import MergeError, merge

ARCH = "test"
MAIN_BLOCKS = 2


def _layer(index: int, seed: float) -> dict[str, np.ndarray]:
    return {
        f"blk.{index}.attn_q.weight": np.full((4, 8), seed + index, dtype=np.float32),
        f"blk.{index}.attn_norm.weight": np.full((8,), seed - index, dtype=np.float32),
    }


def _shared(seed: float) -> dict[str, np.ndarray]:
    return {
        "token_embd.weight": np.arange(32, dtype=np.float32).reshape(4, 8) + seed,
        "output_norm.weight": np.ones((8,), dtype=np.float32),
    }


def _write(
    path: Path,
    *,
    block_count: int,
    recurrent: list[bool],
    nextn: int | None,
    tensors: dict[str, np.ndarray],
) -> None:
    writer = gguf.GGUFWriter(path, ARCH)
    writer.add_string("general.name", "fixture")
    writer.add_uint32(f"{ARCH}.block_count", block_count)
    writer.add_array(f"{ARCH}.attention.recurrent_layers", recurrent)
    if nextn is not None:
        writer.add_uint32(f"{ARCH}.nextn_predict_layers", nextn)
    for name, data in tensors.items():
        writer.add_tensor(name, data)
    writer.write_header_to_file()
    writer.write_kv_data_to_file()
    writer.write_tensors_to_file()
    writer.close()


def _main_file(path: Path) -> Path:
    tensors = {**_shared(0.0), **_layer(0, 1.0), **_layer(1, 1.0)}
    _write(
        path,
        block_count=MAIN_BLOCKS,
        recurrent=[True, False],
        nextn=None,
        tensors=tensors,
    )
    return path


def _draft_file(
    path: Path,
    *,
    shared_seed: float = 0.0,
    recurrent: list[bool] | None = None,
    block_count: int = MAIN_BLOCKS + 1,
) -> Path:
    tensors = {
        **_shared(shared_seed),
        **_layer(2, 5.0),
        "blk.2.nextn.eh_proj.weight": np.full((8, 16), 7.0, dtype=np.float32),
    }
    _write(
        path,
        block_count=block_count,
        recurrent=recurrent if recurrent is not None else [True, False, False],
        nextn=1,
        tensors=tensors,
    )
    return path


def _value(reader: gguf.GGUFReader, key: str) -> object:
    field = reader.get_field(key)
    assert field is not None
    return field.contents()


def test_appends_nextn_layers_and_extends_metadata(tmp_path: Path) -> None:
    out = tmp_path / "out.gguf"
    merge(_main_file(tmp_path / "main.gguf"), _draft_file(tmp_path / "draft.gguf"), out)

    reader = gguf.GGUFReader(out)
    assert _value(reader, gguf.Keys.General.ARCHITECTURE) == ARCH
    assert _value(reader, "general.name") == "fixture"
    assert _value(reader, f"{ARCH}.block_count") == 3
    assert _value(reader, f"{ARCH}.nextn_predict_layers") == 1
    assert _value(reader, f"{ARCH}.attention.recurrent_layers") == [True, False, False]

    names = [tensor.name for tensor in reader.tensors]
    assert names == [
        "token_embd.weight",
        "output_norm.weight",
        "blk.0.attn_q.weight",
        "blk.0.attn_norm.weight",
        "blk.1.attn_q.weight",
        "blk.1.attn_norm.weight",
        "blk.2.attn_q.weight",
        "blk.2.attn_norm.weight",
        "blk.2.nextn.eh_proj.weight",
    ]
    expected = {
        **_shared(0.0),
        **_layer(0, 1.0),
        **_layer(1, 1.0),
        **_layer(2, 5.0),
        "blk.2.nextn.eh_proj.weight": np.full((8, 16), 7.0, dtype=np.float32),
    }
    for tensor in reader.tensors:
        np.testing.assert_array_equal(tensor.data, expected[tensor.name])


def test_rejects_draft_from_other_model(tmp_path: Path) -> None:
    with pytest.raises(MergeError, match="token_embd"):
        merge(
            _main_file(tmp_path / "main.gguf"),
            _draft_file(tmp_path / "draft.gguf", shared_seed=1.0),
            tmp_path / "out.gguf",
        )


def test_rejects_per_layer_array_disagreeing_with_main(tmp_path: Path) -> None:
    with pytest.raises(MergeError, match="recurrent_layers"):
        merge(
            _main_file(tmp_path / "main.gguf"),
            _draft_file(tmp_path / "draft.gguf", recurrent=[False, False, False]),
            tmp_path / "out.gguf",
        )


def test_rejects_block_count_mismatch(tmp_path: Path) -> None:
    with pytest.raises(MergeError, match="層数"):
        merge(
            _main_file(tmp_path / "main.gguf"),
            _draft_file(
                tmp_path / "draft.gguf",
                recurrent=[True, False, False, False],
                block_count=MAIN_BLOCKS + 2,
            ),
            tmp_path / "out.gguf",
        )


def test_rejects_main_that_already_has_nextn(tmp_path: Path) -> None:
    draft = _draft_file(tmp_path / "draft.gguf")
    with pytest.raises(MergeError, match="既にNextN層"):
        merge(draft, draft, tmp_path / "out.gguf")
