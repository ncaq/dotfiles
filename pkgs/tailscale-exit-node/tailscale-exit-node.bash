#!/usr/bin/env bash
set -euo pipefail

# tailscale pingのレイテンシでローカルネットワークにいるかを判定し、
# exit nodeの設定を切り替えるスクリプト。
# ローカルネットワークなら`0s`か数ms、
# 外部なら数10ms以上になります。
#
# NetworkManagerのdispatcherスクリプトとして呼ばれます。
# `$1`がインターフェース名、`$2`がアクション。

# upイベント以外は無視
if [ "${2:-}" != "up" ]; then
  exit 0
fi

# tailscaledの準備完了を最大30秒待つ。
# systemdのserviceを介して待つとdispatcherからの同期起動で依存が循環するため、
# scriptローカルで待つ。
timeout 30 bash -c \
  'until tailscale status --peers=false >/dev/null 2>&1; do sleep 1; done' || true

# tailscale pingでレイテンシを取得
# 出力例: pong from seminar (100.82.4.93) via 192.168.10.88:41641 in 4ms
ping_output=$(tailscale ping -c 1 seminar 2>&1) || true
# 単位込みの値を抽出
# マッチしない場合(ping失敗など)は空文字列のままにする。
# `set -o pipefail`と`errexit`があるため、
# `grep`の非ゼロ終了でスクリプトが落ちないよう`|| true`で守る。
latency=$(echo "$ping_output" | grep -oP 'in \K[0-9]+m?s' || true)
# 正規表現に当てはまらない場合は非常に大きな値を設定して外部とみなす
latency_ms=$(echo "$latency" | grep -oP '[0-9]+(?=ms)' || echo "99999")

# レイテンシが10ms以下ならローカルネットワーク
# `0s`は特別扱いします
if [ "$latency" = "0s" ] || [ "$latency_ms" -le 10 ]; then
  echo "seminar latency is ${latency} (local network), disabling exit node"
  tailscale set --exit-node=
else
  echo "seminar latency is ${latency} (external network), enabling exit node"
  tailscale set --exit-node=seminar
fi
