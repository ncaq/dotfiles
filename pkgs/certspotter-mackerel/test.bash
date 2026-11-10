#!/usr/bin/env bash
set -euo pipefail

# `certspotter-hook`が書いた行を`check-certspotter`がそのまま読めることを、
# 本物と同じ2つのプログラムで検査する。
# ログはカレントディレクトリ相対のパスにして、systemdの状態確認は省く。
#
# 検査するのは以下。
#
# - ログが無ければOK
# - タブや改行や行区切りなどを含むイベントを記録しても、
#   ログの行数はイベント数と一致し、
#   チェック出力は見出し1行とイベントごとに1行でCRITICAL
# - 出力にタブや行区切りや双方向制御やゼロ幅文字が漏れない
# - 証明書のJSONが読めなくてもhookは落ちず、
#   `dns_names`を空にして理由を`dns_names_error`に残し、チェックの出力にも出る
# - アラート期間より古いイベントだけならOK
# - 壊れた行が混ざっても落ちない
# - 古いイベントと新しいイベントが混ざっていたら新しいものだけを出してCRITICAL
# - 必須の環境変数が無ければhookは非0で終わり、チェックはUNKNOWNになる
#
# 引数:
#   $1 ラッパーで包む前の`certspotter-hook`
#   $2 ラッパーで包む前の`check-certspotter`

hook=$1
check=$2

alert_window_seconds=86400

export CERTSPOTTER_EVENTS_LOG=events.log
export CERTSPOTTER_ALERT_WINDOW_SECONDS=$alert_window_seconds
# 空にしてsystemdの状態確認を省く。
export CERTSPOTTER_SERVICE_UNIT=

# hookを通さずにログへ1行書く時の、時刻と`summary`だけを変えた行を出す。
event_line() {
  printf '{"time":%d,"event":"discovered_cert","summary":"%s","dns_names":[],"issuer":""}\n' \
    "$1" "$2"
}

# チェックの終了コードと出力を取る。
# `set -e`の下で非0を扱うため`if`で受ける。
run_check() {
  if output=$("$check"); then
    code=0
  else
    code=$?
  fi
}

run_check
if [ "$code" -ne 0 ] || [ "$output" != "certspotter OK (no events yet)" ]; then
  echo "no-log: 期待 exit 0 'certspotter OK (no events yet)' 実際 exit $code '$output'" >&2
  exit 1
fi

# タブと改行に加えて、行区切り(U+2028)と双方向制御(U+202E)とゼロ幅空白(U+200B)も混ぜる。
# UTF-8のバイト列で書いているのは、
# bashの`$' '`がロケールに依存するため。
echo '{"dns_names":["ncaq.net","*.ncaq.net"]}' >cert.json
env EVENT=discovered_cert \
  SUMMARY=$'cert\tdiscovered\nfor\xe2\x80\xa8ncaq.net\xe2\x80\xae' \
  ISSUER_DN=$'CN=R12\tO=Evil\xe2\x80\x8b' \
  JSON_FILENAME="$PWD/cert.json" \
  "$hook"
env EVENT=error SUMMARY="log unreachable" "$hook"
# `event`はcertspotterが決める値だが、ログが壊れた時にも1行に収まることを見る。
printf '{"time":%d,"event":"evil\\nevent","summary":"","dns_names":[],"issuer":""}\n' \
  "$(date +%s)" >>events.log

lines=$(wc -l <events.log)
if [ "$lines" -ne 3 ]; then
  echo "record: 期待 3行 実際 ${lines}行" >&2
  cat events.log >&2
  exit 1
fi

run_check
output_lines=$(printf '%s\n' "$output" | wc -l)
if [ "$code" -ne 2 ] || [ "$output_lines" -ne 4 ]; then
  echo "recent: 期待 exit 2 4行 実際 exit $code ${output_lines}行" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
for forbidden in $'\t' $'\xe2\x80\xa8' $'\xe2\x80\xae' $'\xe2\x80\x8b'; do
  if printf '%s' "$output" | LC_ALL=C grep -q -F "$forbidden"; then
    echo "recent: 出力に制御文字が漏れています: $(printf '%s' "$forbidden" | od -An -tx1)" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
done
if ! printf '%s' "$output" | grep -q 'ncaq.net,\*.ncaq.net'; then
  echo "recent: dns_namesが出力に含まれていません" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

# `dnsNamesOf`が証明書のJSONを読めない時に、
# `dns_names`を空にしてイベント自体は記録することを見る。
echo 'not json' >broken.json
echo '{"dns_names":"ncaq.net"}' >not-array.json
: >events.log
for json in "$PWD/missing.json" "$PWD/broken.json" "$PWD/not-array.json"; do
  if ! env EVENT=discovered_cert SUMMARY="unreadable cert json" JSON_FILENAME="$json" "$hook"; then
    echo "unreadable-json: hookが非0で終了しました: $json" >&2
    exit 1
  fi
done
lines=$(wc -l <events.log)
empty_lines=$(grep -c -F '"dns_names":[]' events.log || true)
error_lines=$(grep -c -F '"dns_names_error":' events.log || true)
if [ "$lines" -ne 3 ] || [ "$empty_lines" -ne 3 ] || [ "$error_lines" -ne 3 ]; then
  echo "unreadable-json: 期待 3行とも dns_names が空で dns_names_error あり" >&2
  echo "unreadable-json: 実際 ${lines}行中 空${empty_lines}行 理由${error_lines}行" >&2
  cat events.log >&2
  exit 1
fi
run_check
if [ "$code" -ne 2 ] || ! printf '%s' "$output" | grep -q -F 'dns_names_error='; then
  echo "unreadable-json: 期待 exit 2 で出力に dns_names_error= を含む 実際 exit $code" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

# アラート期間より古い行と壊れた行だけなら、黙ってOKになることを見る。
old=$(($(date +%s) - 2 * alert_window_seconds))
event_line "$old" old >events.log
echo 'not json' >>events.log
run_check
if [ "$code" -ne 0 ] || [ "$output" != "certspotter OK" ]; then
  echo "old-only: 期待 exit 0 'certspotter OK' 実際 exit $code '$output'" >&2
  exit 1
fi

# 古い行と新しい行が混ざっている時に、新しい行だけを出すことを見る。
event_line "$(date +%s)" fresh >>events.log
run_check
output_lines=$(printf '%s\n' "$output" | wc -l)
if [ "$code" -ne 2 ] || [ "$output_lines" -ne 2 ]; then
  echo "mixed: 期待 exit 2 2行 実際 exit $code ${output_lines}行" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi
if printf '%s' "$output" | grep -q -F 'old' || ! printf '%s' "$output" | grep -q -F 'fresh'; then
  echo "mixed: 古いイベントが混ざっているか、新しいイベントが欠けています" >&2
  printf '%s\n' "$output" >&2
  exit 1
fi

# 必須の環境変数が無い時に、黙って正常扱いにしないことを見る。
if env --unset=CERTSPOTTER_EVENTS_LOG EVENT=error "$hook" 2>/dev/null; then
  echo "missing-env: ログの指定が無いのにhookが正常終了しました" >&2
  exit 1
fi
unset CERTSPOTTER_ALERT_WINDOW_SECONDS
run_check
if [ "$code" -ne 3 ]; then
  echo "missing-env: 期待 exit 3 実際 exit $code '$output'" >&2
  exit 1
fi
export CERTSPOTTER_ALERT_WINDOW_SECONDS=not-a-number
run_check
if [ "$code" -ne 3 ]; then
  echo "invalid-env: 期待 exit 3 実際 exit $code '$output'" >&2
  exit 1
fi
