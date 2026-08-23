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
{
  local.openWebui.environment = {
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
    # あちらは`HF_HUB_OFFLINE`も立てるため、
    # 後述の埋め込みモデルをHugging Faceから取得できなくなる。
    ENABLE_VERSION_UPDATE_CHECK = "False";

    # 既定の`sentence-transformers/all-MiniLM-L6-v2`は英語専用の小型モデルで、
    # `blue-prompt.nix`が登録する日本語のKnowledgeをほとんど引けない。
    #
    # 実際のKnowledgeの134ファイルを`CHUNK_SIZE`と`CHUNK_OVERLAP`の既定値で分割し、
    # 日本語の質問を10問引かせて比較した結果は以下の通りだった。
    # 並べたのは`RAG_TOP_K`の既定値である上位3件に正解が入った問題数とMRRである。
    #
    # - all-MiniLM-L6-v2: 5問, 0.314
    # - multilingual-e5-small: 8問, 0.670
    # - ruri-v3-70m: 8問, 0.768
    # - multilingual-e5-large: 9問, 0.764
    # - ruri-v3-310m: 9問, 0.858
    #
    # 日本語特化のruri-v3-310mが最も強いが、
    # 他の言語の文書を入れる可能性と利用実績の多さを取ってe5-largeにする。
    # 本格的な選定は別途行う。
    RAG_EMBEDDING_MODEL = "intfloat/multilingual-e5-large";

    # e5系はクエリと文書を別のprefixで区別する前提で学習されている。
    # 付けないと質問と文書が同じ空間の同じ扱いになり、
    # 短い質問から長い文書を引く非対称な検索の精度が落ちる。
    RAG_EMBEDDING_QUERY_PREFIX = "query: ";
    RAG_EMBEDDING_CONTENT_PREFIX = "passage: ";

    # 既定値は1で、chunkを1件ずつ埋め込む。
    # Knowledgeの取り込みはchunkの数だけモデルの呼び出しを繰り返すため、
    # 行列演算をまとめられない分がそのまま待ち時間になる。
    # コンテナのメモリ上限に対してe5-largeの重みは小さく、
    # この程度のバッチなら同時に載せても余裕がある。
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
