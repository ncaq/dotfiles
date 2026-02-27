---
description: Nixプロジェクトのフォーマットとチェックを実行
allowed-tools:
  - Bash(git add *)
  - Bash(nix fmt *)
  - Bash(nix-fast-build *)
---

Nixで管理しているプロジェクトが正常かチェックします。

1. NixはGitでトラッキングされていないファイルを無視するため、`git add --all`で全ての変更をステージングする
2. `nix fmt`でフォーマットを実行する。失敗した場合はエラーを報告して終了
3. nix fmtが成功した場合のみ`nix-fast-build`でプロジェクト全体をチェックする
