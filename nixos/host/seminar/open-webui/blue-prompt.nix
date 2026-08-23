# blue-promptのスキルから生成したワークスペースModelとKnowledgeをOpen WebUIへ登録する。
#
# Open WebUIにはスキルのオンデマンド読み込みが無いため、
# 人格を与えるスキルは内容をシステムプロンプトへ焼き込んだModelとして事前に登録し、
# 事実を引くだけのスキルはModelから参照できるKnowledgeとして登録しておく。
# どちらも他のチャット履歴と同じくOpen WebUIのDBに持つ状態なので、
# Nixで宣言できるのは同期を行うサービスの側だけになる。
{
  lib,
  config,
  inputs,
  ...
}:
let
  # 人がブラウザで開くのと同じURL。
  # Open WebUI自身へ渡す`WEBUI_URL`と同じ値を`option.nix`から引く。
  url = config.local.openWebui.url;
in
{
  imports = [ inputs.blue-prompt.nixosModules.default ];

  # `lib.head`は空リストへ`head: empty list`としか言いません。
  # 役割のリストは空を許す型で、
  # 実際CPUで推論するホストの`freedom`は空にしてあります。
  # CUDAのホストからも消した時に原因の分からないエラーで評価が落ちるのを防ぎます。
  assertions = [
    {
      assertion = config.local.ollama.models.cuda.freedom != [ ];
      message = "blue-promptのModelは表現の自由度を優先したモデルを上流に使うため、local.ollama.models.cuda.freedomが空であってはなりません。";
    }
  ];

  blue-prompt.open-webui = {
    enable = true;
    inherit url;
    # 推論に使う上流モデル。
    # 拒否挙動を除去してあるので、
    # キャラクターの人格を演じるスキルが安全側へ倒れて崩れることが少ない。
    #
    # seminar自身ではなくCUDAのホストのモデルを指す。
    # Open WebUIの上流は`ollama-backend.nix`のCaddyがbulletを優先して選ぶため、
    # ここで要るのは接続先のハードウェアで選ばれた名前の方である。
    # seminarのOllamaへフォールバックした場合は、
    # CPUでは表現の自由度を優先したモデルを置いていないので、このModelは応答できない。
    baseModelId = lib.head config.local.ollama.models.cuda.freedom;
    # コンテナのOpen WebUIは`WEBUI_AUTH = "False"`で動いているため、
    # APIキーを渡さなくても書き込みできる。
  };

  systemd.services.blue-prompt-open-webui-sync = {
    # Serviceがadvertiseされる前に同期が走ると名前を引けても接続先が居ない。
    # Serveの登録はRemainAfterExitのoneshotなので、
    # afterで完了まで待てば登録の後に同期が走る。
    requires = [ "tailscale-serve-open-webui.service" ];
    after = [
      "tailscale-serve-open-webui.service"
      # コンテナへの追従は後述。
      "container@open-webui.service"
    ];
    # RAGのプロンプトテンプレートはインスタンス全体の設定としてAPIで書き込まれる。
    # コンテナは`ENABLE_PERSISTENT_CONFIG = "False"`で動いていて、
    # この種の設定はDBへ残らずプロセス内にしか無いため、
    # コンテナが再起動するとOpen WebUI標準の英語のテンプレートへ戻ってしまう。
    # 同期はRemainAfterExitのoneshotなので放っておくと再実行されず、
    # 人格側のModelの話し方が壊れたまま気付かれずに残る。
    # コンテナの起動と停止に追従させて、その度に同期をやり直す。
    #
    # `partOf`ではなく`bindsTo`にするのは、
    # `partOf`がsystemdの明示的なstopやrestartのジョブでしか伝播しないため。
    # コンテナが異常終了して起動し直された場合には、
    # 同期は`active (exited)`のまま残り、
    # `wantedBy`のWantsは既にactiveなユニットを再実行しない。
    # `bindsTo`なら予期しない停止でも同期がinactiveへ落ちて、
    # 次のコンテナ起動で確実に引き込み直される。
    # `mcp-nixos.nix`の`mcp-nixos-traffic-control`も同じ形で追従させている。
    wantedBy = [ "container@open-webui.service" ];
    bindsTo = [ "container@open-webui.service" ];
    # Knowledgeのアップロードでは1ファイルごとに埋め込みがコンテナ内で走る。
    # 断片の数だけ時間が積み上がるため、
    # oneshotの既定のタイムアウトで中断されて中途半端な状態が残るのを念のため避ける。
    #
    # 上限を外さないのは、
    # このユニットがoneshotでmulti-user.targetに紐付いているためで、
    # 同期が詰まるとboot時のtarget到達と`./install.sh`のactivationが待ち続けてしまう。
    # 同期側はリクエストごとに.NETの既定の100秒で打ち切るので、
    # 断片の数から全体の上限も見積もれる。
    # 余裕を持った有限値にしておけば、
    # 想定を超えた時はfailとしてジャーナルに残って気付ける。
    serviceConfig = {
      TimeoutStartSec = "1h";
      # コンテナの起動が終わった時点では、
      # nspawnがbootしただけで中のOpen WebUIはまだlistenしていない。
      # 上流のヘルス待ちは5秒の試行と2秒の待機を30回で打ち切るため、
      # 猶予は3分半で、
      # 埋め込みモデルの取得やDB migrationを伴う寒い起動では待ち切れずに諦める。
      # 1試行が5秒を使い切るのは`tailscale-serve.nix`の中継が接続を再試行するからで、
      # 即座に502を返す設定にするとこの猶予はもっと短くなる。
      #
      # 恒久的に起動できない状態で短い間隔の再試行を繰り返さないよう、
      # nixpkgsの`ollama-model-loader`と同じ指数バックオフを使う。
      Restart = "on-failure";
      RestartSec = "1s";
      RestartMaxDelaySec = "2h";
      RestartSteps = 10;
    };
  };
}
