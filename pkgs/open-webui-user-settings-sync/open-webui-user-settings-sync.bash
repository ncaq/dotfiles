#!/usr/bin/env bash
set -euo pipefail

# Open WebUIの利用者ごとの設定とプロフィールを、宣言した内容へ揃えるスクリプト。
#
# `WEBUI_AUTH`を無効にしたインスタンスのadminとしてサインインし、
# 宣言と実体に差分がある時だけAPIで書き込みます。
#
# 環境変数:
#   OPEN_WEBUI_URL                        Open WebUIのURL。末尾に`/`は付けません。
#   OPEN_WEBUI_DECLARED_SETTINGS_FILE     `settings.ui`へ重ねる鍵を書いたJSONファイル。
#   OPEN_WEBUI_SYSTEM_PROMPT_FILE         システムプロンプトのテキストファイル。
#   OPEN_WEBUI_DECLARED_PROFILE_FILE      プロフィールの列を書いたJSONファイル。
#   OPEN_WEBUI_PROFILE_IMAGE_FILE         プロフィールのアイコンにするWebPの画像ファイル。
#   OPEN_WEBUI_USER_SETTINGS_MERGE_FILTER 設定をマージするjqのフィルタのファイル。
#                                         `default.nix`のラッパーが設定します。

# bashはエラーの頭に変数名を付けるので、メッセージには変数名を書かない。
url=${OPEN_WEBUI_URL:?is not set}
declared_settings_file=${OPEN_WEBUI_DECLARED_SETTINGS_FILE:?is not set}
system_prompt_file=${OPEN_WEBUI_SYSTEM_PROMPT_FILE:?is not set}
declared_profile_file=${OPEN_WEBUI_DECLARED_PROFILE_FILE:?is not set}
profile_image_file=${OPEN_WEBUI_PROFILE_IMAGE_FILE:?is not set}
merge_filter=${OPEN_WEBUI_USER_SETTINGS_MERGE_FILTER:?is not set}

# 比較の前にJSONの鍵の順序と空白を揃える。
normalize() {
  jq --compact-output --sort-keys "${1:-.}"
}

# コンテナがbootした時点ではまだOpen WebUIはlistenしていない。
# 埋め込みモデルの取得やDB migrationを伴う起動では待ち時間が長くなるため、
# 接続が拒否される間も再試行して起動を待つ。
#
# 猶予は回数ではなく`--retry-max-time`で決める。
# 接続を拒否される間は1回の試行が即座に返るため、
# 回数で数えると猶予がそのまま`--retry-delay`の累計になり、
# 30回では1分にしかならない。
# `blue-prompt.nix`が上流のヘルス待ちに見積もる3分半にも届かず、
# 寒い起動では待ち切る前に諦めてしまう。
curl --fail --silent --show-error --output /dev/null \
  --retry 300 --retry-delay 2 --retry-max-time 600 --retry-connrefused --max-time 10 \
  "$url/health"

# `WEBUI_AUTH`を無効にしたインスタンスのadminとしてサインインする。
# この組は`routers/auths.py`のsigninが無効時に使う定数そのもので、
# 秘密ではなく、認証が無効である以上これ以外の資格情報は存在しない。
#
# 得たトークンは以降の`Authorization`ヘッダとしてcurlの引数に載るため、
# 実行中は同じホストの他の利用者から`/proc`で読める。
# それでも隠さないのは隠しても何も守れないからで、
# このスクリプト自体が誰でも読めるストアにあり、
# 上の資格情報を読めば同じトークンをいつでも取り直せる。
token=$(
  curl --fail --silent --show-error --max-time 30 \
    --request POST "$url/api/v1/auths/signin" \
    --header 'Content-Type: application/json' \
    --data '{"email":"admin@localhost","password":"admin"}' |
    jq --raw-output '.token'
)

# curlは応答が2xxである限り成功するため、
# 中身が期待した形でなかった場合はここで落としておく。
# 空のトークンをそのまま使うと、
# 認証の失敗ではなく設定の取得の失敗として現れて原因が分かりにくい。
if [ -z "$token" ] || [ "$token" = null ]; then
  echo "サインインの応答からトークンを取り出せませんでした" >&2
  exit 1
fi

# Modelの登録と違い、この経路はトークンを要求する。
current=$(
  curl --fail --silent --show-error --max-time 30 \
    --header "Authorization: Bearer $token" \
    "$url/api/v1/users/user/settings"
)

# 利用者の設定が一度も書かれていなければ応答はnullになる。
#
# マージのフィルタは隣の`user-settings-merge.jq`にあり、
# `merge-test.nix`が同じファイルを検査する。
next=$(
  jq --null-input \
    --argjson current "$current" \
    --argjson declared "$(<"$declared_settings_file")" \
    --rawfile system "$system_prompt_file" \
    --from-file "$merge_filter"
)

# 差分が無い時に書きに行かないのは、
# コンテナが起動するたびに`updated_at`だけが進むのを避けるためである。
if [ "$(normalize '(. // {}).ui // {}' <<<"$current")" = "$(normalize <<<"$next")" ]; then
  echo "利用者の設定は宣言と一致しています"
else
  jq --null-input --argjson ui "$next" '{ ui: $ui }' |
    curl --fail --silent --show-error --max-time 30 --output /dev/null \
      --request POST "$url/api/v1/users/user/settings/update" \
      --header "Authorization: Bearer $token" \
      --header 'Content-Type: application/json' \
      --data @-
  echo "利用者の設定を宣言の内容へ更新しました"
fi

# ここからはプロフィールで、受け口も表の列も設定とは別になる。
desiredProfile=$(
  jq --null-input \
    --argjson declared "$(<"$declared_profile_file")" \
    --arg image "data:image/webp;base64,$(base64 --wrap 0 "$profile_image_file")" \
    '$declared + { profile_image_url: $image }'
)

# 比較する列を宣言の側から導く。
# 応答には`email`や`role`のようにこちらが決めない列も並ぶので、
# 固定で書くと宣言を増やした時に比較へ足し忘れる。
#
# POSTの前後の両方で同じ形を取るため関数にする。
fetchCurrentProfile() {
  curl --fail --silent --show-error --max-time 30 \
    --header "Authorization: Bearer $token" \
    "$url/api/v1/auths/" |
    jq --argjson desired "$desiredProfile" \
      '. as $current | $desired | keys | map({ key: ., value: $current[.] }) | from_entries'
}

currentProfile=$(fetchCurrentProfile)

if [ "$(normalize <<<"$currentProfile")" = "$(normalize <<<"$desiredProfile")" ]; then
  echo "プロフィールは宣言と一致しています"
else
  curl --fail --silent --show-error --max-time 30 --output /dev/null \
    --request POST "$url/api/v1/auths/update/profile" \
    --header "Authorization: Bearer $token" \
    --header 'Content-Type: application/json' \
    --data @- <<<"$desiredProfile"

  # `UpdateProfileForm`はPydanticのモデルなので、
  # 宣言に上流が持たない列(将来の削除や綴り間違いを含む)が混ざると、
  # curlは2xxを受け取ったまま値は黙って捨てられる。
  # それに気付かないと差分は解消されず、
  # コンテナが起動するたびに同じPOSTが繰り返される。
  # 書き込み後にもう一度取得して、収束したことまで確かめる。
  afterProfile=$(fetchCurrentProfile)
  if [ "$(normalize <<<"$afterProfile")" = "$(normalize <<<"$desiredProfile")" ]; then
    echo "プロフィールを宣言の内容へ更新しました"
  else
    echo "プロフィールを更新しても宣言と一致しませんでした。宣言に上流が受け付けない列が含まれている可能性があります" >&2
    exit 1
  fi
fi
