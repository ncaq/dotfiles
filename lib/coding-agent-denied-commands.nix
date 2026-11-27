# コーディングエージェントに実行させないコマンドの前置部分。
# Claude CodeとOpenCodeで書式が違うので、
# それぞれのモジュールがこの一覧から権限の規則を作ります。
[
  # npmやPyPIからパッケージを取ってきてすぐ実行するコマンド。
  # インストールの時に任意のコードを実行できるので拒否します。
  # リポジトリ自体のセットアップを含む`npm install`などは許します。
  "bun x"
  "bunx"
  "npm exec"
  "npm x"
  "npx"
  "pip install"
  "pip3 install"
  "pipx run"
  "pnpm dlx"
  "pnpx"
  "python -m pip install"
  "python3 -m pip install"
  "uv pip install"
  "uv run --with"
  "uv tool run"
  "uvx"
  "yarn dlx"
  # ファイルの削除には`trash`を使わせます。
  "rm"
]
