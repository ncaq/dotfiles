# Open WebUIの利用者ごとの設定を宣言してAPIで流し込む。
#
# `environment.nix`が扱うインスタンス全体の設定は`config`表に入り、
# 0.11.0ではその鍵の全てに対応する環境変数がある。
# 対してここで扱うのは`user`表に入る利用者ごとのデータで、
# 環境変数からは一切届かず、HTTP APIで書き込むしかない。
# 認証を無効にしていて利用者は一人しかいないが、
# 置き場としては利用者ごとのデータのままである。
#
# 扱うのは2種類ある。
# `settings`列に入るUIの挙動のJSONと、
# `name`や`profile_image_url`のようなプロフィールの列である。
# 受け口のAPIは別々だが、
# どちらもUIの設定画面から触る同じ性質のものなので1つの同期にまとめる。
# サインインで得たトークンも共有できる。
#
# `ENABLE_PERSISTENT_CONFIG`が効くのは`config`表だけなので、
# こちらはDBへそのまま永続する。
# 環境変数のように毎回の起動で宣言が真になるわけではなく、
# 宣言と実体が一致するのはこの同期が走った時点だけである。
# UIから書き換えれば次にコンテナが起動するまで食い違ったままになる。
{
  lib,
  pkgs,
  config,
  inputs,
  username,
  hardening,
  ...
}:
let
  url = config.local.openWebui.url;

  # プロフィールの列のうち画像以外の宣言。
  #
  # `UpdateProfileForm`の任意の列は送らなくても`None`として書かれるため、
  # 書かないことがそのまま空にするという宣言になる。
  # `bio`を省いているのは空のままにしたいからで、書き忘れではない。
  #
  # `gender`はUIのSettingsSelectが持つ選択肢から取る。
  # 空と`male`と`female`と、自由入力の`custom`がある。
  profile = {
    name = "エヌユル";
    gender = "male";
    date_of_birth = "1996-01-25";
  };

  # プロフィールのアイコン。
  #
  # www.ncaq.netのfaviconと同じ絵にする。
  # 寸法は470x470で、
  # UIから上げた時に縮む版とは大きさが違うが元は同じである。
  #
  # 実体はinputsの中に無い。
  # あちらはgit-lfsで管理されていて、
  # flakeが取得するのはoidとサイズだけを書いたポインタである。
  # `git+https`の`lfs=1`はNixが持っている機能だが、
  # GitHubのbatch APIが422を返すため今のところ使えない。
  #
  # そこで本番のサイトから取る。
  # ハッシュはポインタに書かれたoidをそのまま使えるので、
  # 手で書き写す必要も、inputsの更新に合わせて直す必要も無い。
  # サイトのデプロイがinputsのリビジョンへ追い付いていなければ、
  # ハッシュが合わずにビルドが落ちて気付ける。
  profileImage =
    let
      pointer = builtins.readFile "${inputs.www-ncaq-net}/site/favicon.webp";
      match = builtins.match ".*oid sha256:([0-9a-f]+).*" pointer;
      oid =
        if match == null then
          throw "favicon.webpがgit-lfsのポインタとして読み取れませんでした。git-lfs管理から外れたか、実体そのものに置き換わっています。"
        else
          builtins.elemAt match 0;
    in
    pkgs.fetchurl {
      url = "https://www.ncaq.net/favicon.webp";
      sha256 = oid;
    };

  # 人がブラウザで新しい会話を始めた時に既定で効くシステムプロンプト。
  #
  # home-managerはNixOSのホストではシステムへ統合されているため、
  # `lib/mk-nixos-system.nix`が読み込んだhome-manager側のオプションを直接引ける。
  # 素材を二重に持たずに、他のサービスへ貼るのと同じプロンプトを渡せる。
  #
  # 値はderivationなので、評価時に`readFile`で開くとIFDになる。
  # 同期のスクリプトが`jq --rawfile`で読めば評価は中身を知らずに済む。
  #
  # ミニ版を使うのは文字数の制約があるからではなく、
  # `blue-prompt.nix`が登録する人格のModelと合わさるためである。
  # `middleware.py`はModel側のシステムプロンプトを先に、
  # ブラウザが積んだこちらを後に連結するので、両方が同時に効く。
  # 人格を演じている最中にも噛み合う分量に絞っておきたい。
  systemPromptFile = config.home-manager.users.${username}.prompt.chatAssistantMini;

  # システムプロンプト以外に宣言する設定。
  #
  # ここに書いた鍵だけが上書きされ、書いていない鍵は実体のまま残る。
  # 全置換にしないのは、最後に選んだModelを覚える`models`のように、
  # 人が触った結果をそのまま持たせたい鍵が同じ階層に同居しているためである。
  #
  # `version`は書いてはならない。
  # `ChangelogModal.svelte`が閉じた時に実際の版を書き込む鍵で、
  # 固定の文字列を宣言すると版が上がるたびに食い違う。
  # 変更履歴の自動表示は下の`showChangelog`で止める。
  #
  # `settings`列は自由形式のJSONなので、
  # ここで鍵名を書き間違えても、上流が版を上げて鍵名を変えても、
  # APIはそのまま受け入れて何のエラーも返さない。
  # 効かなくなった鍵があっても値は書き込まれ続けるので、
  # 同期の成功だけを見ていては静かな無効化に気付けない。
  # 上流の版を上げる時は、
  # 変更点(Release Notes)を見てここに書いた鍵の名前がまだ存在するかを、
  # 設定画面のUIかソースの`Settings`配下の該当コンポーネントと突き合わせる。
  #
  # 既定値と同じ値は原則として書かない。
  # 書ける理由が無い上に、
  # 上流が既定を変えた時に宣言が黙って古い値を固定し続けてしまう。
  # 例外は`iframeSandbox`のように、
  # 既定のままであること自体を守りたい場合に限る。
  declared = {
    # アクセスした時に変更履歴のモーダルを自動で出さない。
    #
    # 既定は真で、`+layout.svelte`は`settings.version`が実際の版と異なると表示する。
    # 既読の版が書かれるのは`ChangelogModal.svelte`の閉じるボタンを押した時だけで、
    # Escapeなどで閉じると記録されずに次のアクセスでまた出る。
    # バージョンはflake.lockで固定していて更新の内容は別途確認できるので、
    # 履歴は設定画面のAboutから必要な時に開く。
    showChangelog = false;

    # Enterだけで送信せず、Ctrlとの同時押しを要求する。
    #
    # 既定は偽でEnterがそのまま送信になる。
    # 日本語入力では変換を確定するEnterと送信のEnterが同じ打鍵なので、
    # 書きかけの文が変換の確定と同時に飛んでいく。
    ctrlEnterToSend = true;

    # 入力中にMarkdownの記法が装飾へ自動変換されるのを止める。
    #
    # 入力欄は真偽どちらでも`RichTextInput.svelte`のtiptapで、
    # 素のテキストエリアになるわけではない。
    # 変わるのは`enableInputRules`と`enablePasteRules`で、
    # 既定の真では`**`で囲んだ時点で太字の装飾に変換され、
    # 打った記号そのものは文書から消える。
    # 送信時にturndownでMarkdownへ書き戻されるため、
    # 記法を経由した往復が毎回起きる。
    #
    # 偽にすると2つの規則が無効になり、
    # 貼り付けも強制的にプレーンテキストとして扱われる。
    # 打った記号は記号のまま残るので、
    # 書いた文字列と送られる文字列が食い違わない。
    #
    # Markdownを直接書く用途では往復の揺れが要らない。
    # 表示の側は変わらないので、
    # 受け取った応答は今まで通り整形されて出る。
    richTextInput = false;

    # 添付したファイルを断片ではなく全文でコンテキストへ入れる。
    #
    # 既定の`focused`は、
    # 添付をKnowledgeと同じ経路でchunkへ切り、
    # 埋め込みで引いた断片だけをコンテキストへ入れる。
    # `full`にすると`context`が付いて全文がそのまま渡る。
    #
    # 埋め込みモデルの選定にはまだ課題が残っていて、
    # 断片を引く精度をこちらから保証できない。
    # 添付するのはその場で読ませたい文書なので、
    # 引き当てに失敗して読み落とされるより、
    # 全文を渡して確実に読ませる方が用途に合う。
    #
    # 代償は長い文書でコンテキストを食い潰すことである。
    # これは既定を決めているだけなので、
    # 大きなファイルを渡す時は送信時に個別へ切り替えられる。
    defaultUploadContext = "full";

    # メッセージの横幅の上限を外す。
    #
    # 既定は偽で、`Message.svelte`も`MessageInput.svelte`も幅を絞るクラスを付ける。
    # 27インチの4Kを並べた環境では画面の中央に細い柱が立つだけになる。
    # 折りたたみ端末でも開いた状態なら横幅は足りる。
    widescreenMode = true;

    # 応答が返った時にブラウザの通知を出す。
    #
    # 既定は偽で、`+layout.svelte`はこの値だけを見て`new Notification`を呼ぶ。
    # ローカルで推論を回すと待ち時間が長いので、
    # 別のウィンドウへ移っていても終わりに気付けるようにする。
    #
    # ただしブラウザ側の許可はこの宣言では与えられない。
    # 設定画面のトグルは偽の時にだけ`Notification.requestPermission()`を呼ぶ作りで、
    # 既に真ならば無効にする方向へしか動かない。
    # 宣言で真にするとUIから許可を求める経路には入れなくなるので、
    # 許可はブラウザのサイトごとの設定から与える。
    notificationEnabled = true;

    # 応答が流れてくる間、端末を小刻みに振動させる。
    #
    # 既定は偽。
    # `Chat.svelte`は`navigator.vibrate`を持つ環境で、
    # ストリームのchunkを受け取るたびに5ミリ秒の振動を呼ぶ。
    # 応答が返り終わった合図ではなく、
    # 生成が続く限り震え続ける類の挙動である。
    #
    # 振動する機構を持たないデスクトップでは何も起きないので、
    # 効くのはAndroidのFirefoxで開いた時だけになる。
    hapticFeedback = true;

    # LLMが生成したHTMLを表示する枠のサンドボックスを緩めない。
    #
    # どちらも既定は偽だが、
    # UIのトグル一つで真にできてしまう。
    # 生成物を同一オリジンで走らせると、
    # ブラウザがトークンを置いている`localStorage`へ手が届く。
    # フォームの送信を許せば、
    # 生成されたページが任意の宛先へ入力内容を送れる。
    #
    # 既定と同じ値をあえて宣言するのは、
    # 一度緩めた状態がDBに残り続けるのを防ぐためである。
    iframeSandboxAllowForms = false;
    iframeSandboxAllowSameOrigin = false;
  };

  # 同期のスクリプトの中身は`pkgs/open-webui-user-settings-sync`にある。
  # 宣言はJSONのファイルにして、下のサービスの環境変数でパスを渡す。
  sync = pkgs.callPackage ../../../../pkgs/open-webui-user-settings-sync { };
in
{
  systemd.services.open-webui-user-settings-sync = {
    description = "Sync declarative Open WebUI user settings";

    # Serviceがadvertiseされる前に同期が走ると名前を引けても接続先が居ない。
    requires = [ "tailscale-serve-open-webui.service" ];
    after = [
      "tailscale-serve-open-webui.service"
      "container@open-webui.service"
    ];

    # コンテナの起動と停止に追従させる。
    #
    # `blue-prompt.nix`の追従は`ENABLE_PERSISTENT_CONFIG = "False"`による揮発が理由だが、
    # こちらの`user`表はDBへそのまま永続するので揮発しない。
    # ここでの理由は冒頭のコメントの通り、
    # UIから書き換えられた値を次のコンテナ起動で宣言へ戻すことである。
    #
    # `partOf`ではなく`bindsTo`を選ぶ機構の理由は`blue-prompt.nix`と共通で、
    # `partOf`が明示的なstopやrestartのジョブでしか伝播しないため、
    # 異常終了して起動し直された場合に同期が`active (exited)`のまま取り残される。
    # `bindsTo`なら予期しない停止でも一度inactiveへ落ちて、
    # 次のコンテナ起動で確実に引き込み直される。
    wantedBy = [ "container@open-webui.service" ];
    bindsTo = [ "container@open-webui.service" ];

    # スクリプトが読む環境変数の意味は、
    # `pkgs/open-webui-user-settings-sync/open-webui-user-settings-sync.bash`の冒頭に書いてある。
    environment = {
      OPEN_WEBUI_URL = url;
      OPEN_WEBUI_DECLARED_SETTINGS_FILE = pkgs.writeText "open-webui-declared-settings.json" (
        builtins.toJSON declared
      );
      OPEN_WEBUI_SYSTEM_PROMPT_FILE = systemPromptFile;
      OPEN_WEBUI_DECLARED_PROFILE_FILE = pkgs.writeText "open-webui-declared-profile.json" (
        builtins.toJSON profile
      );
      OPEN_WEBUI_PROFILE_IMAGE_FILE = profileImage;
    };

    serviceConfig = hardening.network // {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe sync;
      DynamicUser = true;

      # ヘルス待ちだけで最大10分を使うため、
      # oneshotの既定の90秒では待ち切る前に殺される。
      # 待った後のAPIの呼び出しも合わせて余裕を持たせる。
      #
      # 上限を外さないのは`blue-prompt.nix`と同じ理由で、
      # 想定を超えた時にfailとしてジャーナルに残って気付けるようにするためである。
      TimeoutStartSec = "15m";

      # 恒久的に起動できない状態で短い間隔の再試行を繰り返さないよう、
      # `blue-prompt.nix`と同じ指数バックオフを使う。
      Restart = "on-failure";
      RestartSec = "1s";
      RestartMaxDelaySec = "2h";
      RestartSteps = 10;
    };
  };
}
