# Open WebUIの設定のうち、環境変数で宣言できるものをまとめる。
#
# Open WebUIの設定は`configs`テーブルにドット区切りのキーで入るが、
# コンテナは`ENABLE_PERSISTENT_CONFIG = "False"`で動いているため、
# 読み取りは常に環境変数から組み立てた既定値を向く。
# つまりここに書いた値がインスタンスの設定そのものになり、
# UIから変更してもプロセスの中にしか残らず再起動で戻る。
#
# 環境変数で届かない設定はHTTP APIで流し込むしかなく、
# それは`blue-prompt.nix`のようにコンテナへ追従する同期の側の仕事になる。
# 環境変数で書けるものをここで押さえておけば、
# 状態を持つ同期に頼る範囲をその分だけ狭められる。
{ lib, config, ... }:
{
  local.openWebui.environment = {
    # nixpkgsのモジュールが`http://localhost:8080`を渡すため、
    # 宣言だけが実際の公開先と食い違った状態になっていた。
    #
    # 0.11.0でこの値を読むのは、
    # フロントエンドへ設定として返す箇所と、
    # Google Programmable Search Engineを検索に使う場合のRefererヘッダだけである。
    # 後者では外部の検索APIへこのURLがそのまま送られるが、
    # tailnetの名前はこのリポジトリで公開しているので隠すべき情報ではない。
    WEBUI_URL = config.local.openWebui.url;

    # YouTubeの字幕を取りに行く言語の優先順。
    # 既定は`en`だけで、日本語の動画を渡しても英語の字幕しか探さない。
    # カンマ区切りで複数指定でき、先に書いた言語から順に試される。
    YOUTUBE_LOADER_LANGUAGE = "ja,en";

    # 音声の書き起こしに使うモデル。
    #
    # `AUDIO_STT_ENGINE`が空なのでコンテナの中でfaster-whisperが動く。
    # 既定の`base`は74Mパラメータで、日本語の書き起こしは実用に耐えない。
    # large-v3のデコーダを32層から4層へ削ったturboは、
    # 品質をlarge-v3の近くに保ったまま速度が大きく上がる。
    #
    # `WHISPER_COMPUTE_TYPE`は既定の`int8`のままにする。
    # CTranslate2はCPUでは`float16`を`float32`へ落とすので選択肢は実質2つしかなく、
    # Zen4は`AVX512_VNNI`を持っていてint8の積和を1命令で回せる。
    # CPUの推論は重みを読み出す帯域で頭打ちになるため、
    # 重みが4分の1で済むこと自体が最も効く。
    #
    # 本格的に書き起こしを回すなら、
    # コンテナのCPUではなくbulletのGPUへ逃がす方が筋が良い。
    # その場合は`AUDIO_STT_ENGINE`をOpenAI互換にして外部のサーバへ投げることになる。
    WHISPER_MODEL = "large-v3-turbo";

    # 無音の区間を落としてから書き起こす。
    #
    # 処理する音声の量が減るぶん速くなり、
    # 無音へwhisperが幻の文字列を吐く現象も抑えられる。
    # 日本語では「ご視聴ありがとうございました」の類が湧くことで知られている。
    WHISPER_VAD_FILTER = "True";

    # 新規チャットの初期画面に出る提案。
    #
    # 既定では英語圏の一般利用者向けの6件が並ぶ。
    # 大学入試の語彙やローマ帝国の豆知識といった内容で、
    # このインスタンスの用途とは何一つ噛み合っていない。
    #
    # 消したいところだが、消す手段が無い。
    # `config.py`は空のリストを渡されると、
    # 環境変数を読んだ直後の`if default_prompt_suggestions == []`で既定へ戻す。
    # JSONのパースに失敗した場合も同じ経路を通る。
    # APIで空にすることはできるが、
    # `ENABLE_PERSISTENT_CONFIG`が無効なのでプロセスの中にしか残らず、
    # 維持するにはコンテナへ追従する同期が要る。
    # 表示を消すためだけに状態を持つ仕組みを増やすのは釣り合わない。
    #
    # 埋めるしかないので、モデルの様子を見るための入口にする。
    # ここはModelを選ぶ前の画面なので、
    # Knowledgeを引けるかどうかのように、
    # 特定のModelでなければ意味を持たない確認は置かない。
    DEFAULT_PROMPT_SUGGESTIONS = builtins.toJSON [
      {
        # 応答が返るか、日本語で返るか、指定した長さを守れるかを一度に見る。
        title = [
          "疎通を確認"
          "自己紹介を3行で"
        ];
        content = "自己紹介を3行でしてください。";
      }
      {
        # thinkingが動いていれば手前で検算する。
        # 動いていなければ小数の比較を間違える定番の問題。
        title = [
          "思考を確認"
          "9.11と9.9の比較"
        ];
        content = "9.11と9.9はどちらが大きいですか。理由も説明してください。";
      }
      {
        # 学習データからは答えられないので、
        # ツールを使わずに答えたらそれはハルシネーションだと分かる。
        title = [
          "ツールを確認"
          "今日の日付"
        ];
        content = "今日の日付を調べてください。";
      }
    ];

    # 上流はOllamaだけなのでOpenAIのAPIは使わない。
    #
    # 単に使わないだけなら放っておいても良さそうに見えるが、
    # `OPENAI_API_BASE_URLS`の既定値が`https://api.openai.com/v1`で、
    # `routers/openai.py`の`get_all_models_responses`はAPIキーの有無で分岐しない。
    # 有効なままだとモデル一覧を更新するたびに、
    # 空のキーを付けたリクエストがapi.openai.comへ実際に飛ぶ。
    ENABLE_OPENAI_API = "False";

    # UIが`/api/version/updates`を叩くたびに、
    # api.github.comのopen-webuiのリリース情報を取りに行く挙動を止める。
    # バージョンはflake.lockで固定しているので、
    # 新しい版が出ていると知らされても通知から動けることはない。
    #
    # 同じ効果は`OFFLINE_MODE`でも得られるが、そちらは使わない。
    # あちらは`HF_HUB_OFFLINE`も立てる。
    # 埋め込みをOllamaへ移した今のコンテナはHugging Faceから何も取得しないが、
    # コンテナ内で推論する設定へ戻した時に離れた場所で壊れて原因を探すことになるので、
    # 止めたい挙動だけを狙えるこちらを使い続ける。
    ENABLE_VERSION_UPDATE_CHECK = "False";

    # 埋め込みはコンテナ内のsentence-transformersではなくOllamaで行う。
    #
    # 接続先の`RAG_OLLAMA_BASE_URL`は未指定なら`OLLAMA_BASE_URL`を使うので、
    # チャットと同じCaddyのフェイルオーバー(bullet優先、seminarへ退避)をそのまま通る。
    # モデルはGGUFに`num_gpu 0`を焼き込んで登録しているため、
    # bulletで受けてもGPUには載らず、デスクトップ用途とVRAMを取り合わない。
    #
    # 同じモデルならエンジンを変えても検索精度は変わらないことと、
    # GGUFのCPU推論がtorchのfp32よりbulletで約2.5倍、seminarでも約1.8倍速いことは、
    # blue-promptのKnowledge 10011チャンクと20問の実測で確認した。
    # ref https://github.com/ncaq/blue-prompt/issues/171
    RAG_EMBEDDING_ENGINE = "ollama";

    # 既定の`sentence-transformers/all-MiniLM-L6-v2`は英語専用の小型モデルで、
    # `blue-prompt.nix`が登録する日本語のKnowledgeをほとんど引けない。
    # 上記の実測ではmultilingual-e5-largeがtop3命中率0.70/MRR 0.605で、
    # 測った中のMRR首位はbge-m3の0.640だった。
    # 差は20問では統計的に語れないため、
    # 実測済みで現行と埋め込みが変わらないe5-largeを維持して、
    # モデルの乗り換えはblue-prompt#196の決着に任せる。
    #
    # 名前の実体は`lib/ollama-model-names.nix`にあり、
    # GGUFの登録は`nixos/ollama/model.nix`が行う。
    RAG_EMBEDDING_MODEL = lib.head config.local.ollama.models.embedding;

    # e5系はクエリと文書を別のprefixで区別する前提で学習されている。
    # 付けないと質問と文書が同じ空間の同じ扱いになり、
    # 短い質問から長い文書を引く非対称な検索の精度が落ちる。
    #
    # Ollamaエンジンではprefixは本文の先頭へ文字列として連結される。
    # `RAG_EMBEDDING_PREFIX_FIELD_NAME`は設定してはいけない。
    # 設定するとprefixがリクエストJSONの別フィールドへ移るが、
    # Ollamaの`/api/embed`に受け皿が無く未知フィールドとして黙って捨てられるため、
    # prefixがどこにも付かないままエラーにもならない。
    RAG_EMBEDDING_QUERY_PREFIX = "query: ";
    RAG_EMBEDDING_CONTENT_PREFIX = "passage: ";

    # 既定値は1で、chunkを1件ずつ埋め込む。
    # Knowledgeの取り込みはchunkの数だけ呼び出しを繰り返すため、
    # Ollamaエンジンでは1回の`/api/embed`へまとめて渡す件数がこれになる。
    # バッチにできない分がそのまま往復と起動の待ち時間になる。
    RAG_EMBEDDING_BATCH_SIZE = "32";

    # ノートやカレンダーなどの組み込みツールを既定で渡さない。
    # Open WebUIはOllamaが申告するcapabilitiesを見ないため、
    # tools非対応のモデルにもfunction callingを要求してしまい、
    # `does not support tools`で会話そのものが失敗する。
    # モデル個別の設定が優先されるので、
    # 対応モデルだけUIから有効化できる。
    DEFAULT_MODEL_METADATA = builtins.toJSON { capabilities.builtin_tools = false; };
  };
}
