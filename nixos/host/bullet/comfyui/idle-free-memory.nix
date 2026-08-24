# アイドル中のComfyUIにメモリを解放させる常駐プロセスを、コンテナの中で動かす。
#
# 何をどう判断して解放するかは`idle-free-memory.py`の先頭に書いてある。
#
# ホスト側のサービスにしない理由は寿命の管理である。
# ComfyUIのコンテナはソケットアクティベーションで起きるので、
# ホストに置くと`container@comfyui.service`への`bindsTo`と`after`と`wantedBy`で、
# 起動と停止を追従させる配線が要る。
# コンテナの中のサービスなら、コンテナが消える時に一緒に消える。
#
# 隔離の観点でも中に置いて構わない。
# 外部由来のコードと同じ空間へ自分のコードを入れることになるが、
# このプロセスが持つ権限はComfyUIのAPIを叩けることだけで、
# それは同じ空間にいるComfyUI自身が最初からできることである。
#
# 宛先がループバックになるので、
# vethのアドレスもコンテナのfirewallも関係しなくなる。
{ hardening, ... }:
{
  containers.comfyui.config =
    {
      pkgs,
      config,
      ...
    }:
    {
      systemd.services.comfyui-idle-free-memory = {
        description = "Free ComfyUI memory while idle";
        wantedBy = [ "multi-user.target" ];
        after = [ "comfyui.service" ];
        # 依存関係で縛らない。
        # ComfyUIが落ちている間はHTTPが失敗するだけで、
        # スクリプトはそれを記録して次の周回へ進む。
        # 縛って止めるより、動いていない相手を叩き続けて勝手に復帰する方が単純である。
        environment = {
          # 渡すのはホストとポートだけにする。
          # `http://`をこちらで足して完全なURLにすると、
          # Python側で`urlopen`へ渡るのが変数になり、
          # ruffがS310でスキームを確定できないと警告する。
          # 理由の詳細は`idle-free-memory.py`の冒頭にある。
          COMFYUI_AUTHORITY = "127.0.0.1:${toString config.services.comfyui.port}";
          # 確認の間隔。
          # 活動時刻はComfyUI自身の記録から取るので、
          # 間隔を詰めても取りこぼしは減らない。
          # 解放が実際に走るのが最後の活動から`IDLE_SECONDS`後ちょうどではなく、
          # そこから最大でこの秒数だけ遅れる、という意味しか持たない。
          POLL_INTERVAL_SECONDS = "300";
          # これだけ何もしていなければ解放する。
          # 短くすると、少し考えてから次の生成を回す間に降ろされて載せ直しになる。
          IDLE_SECONDS = "600";
        };
        # `hardening`はこのファイル自身がホスト側のモジュールとして受け取ったものである。
        # コンテナの中のモジュールへはモジュール引数としては渡らないが、
        # ここはクロージャの内側なのでそのまま参照できる。
        serviceConfig = hardening.network // {
          # ループバックへHTTPを投げるだけなので、
          # 標準ライブラリしか使わないPythonをそのまま動かせる。
          ExecStart = "${pkgs.python3}/bin/python3 ${./idle-free-memory.py}";
          DynamicUser = true;
          # 待ち続けるのが仕事なので、終了は全て異常である。
          Restart = "always";
          RestartSec = "10s";
        };
      };
    };
}
