"""`merge-gguf-nextn`コマンドの入口を検査する。"""

import sys
from pathlib import Path

import pytest

from merge_gguf_nextn import cli
from merge_gguf_nextn.merge import MergeError


def test_passes_main_draft_output_in_order(monkeypatch: pytest.MonkeyPatch) -> None:
    # `lib/quantize-gguf-with-nextn.nix`は位置引数で呼ぶので、順番を固定する。
    calls: list[tuple[Path, Path, Path]] = []

    def fake_merge(main: Path, draft: Path, output: Path) -> None:
        calls.append((main, draft, output))

    monkeypatch.setattr(cli, "merge", fake_merge)
    monkeypatch.setattr(sys, "argv", ["merge-gguf-nextn", "a.gguf", "b.gguf", "c.gguf"])
    cli.main()
    assert calls == [(Path("a.gguf"), Path("b.gguf"), Path("c.gguf"))]


def test_reports_merge_error_and_exits_with_1(
    monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    def fake_merge(main: Path, draft: Path, output: Path) -> None:
        raise MergeError("噛み合いません")

    monkeypatch.setattr(cli, "merge", fake_merge)
    monkeypatch.setattr(sys, "argv", ["merge-gguf-nextn", "a.gguf", "b.gguf", "c.gguf"])
    with pytest.raises(SystemExit) as exit_info:
        cli.main()
    assert exit_info.value.code == 1
    assert capsys.readouterr().err == "merge-gguf-nextn: 噛み合いません\n"
