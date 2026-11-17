# アイドル中のComfyUIにメモリを解放させる常駐プロセス。
#
# 何をどう判断して解放するかは`src/IdleFreeMemory/Run.hs`の冒頭に書いてある。
#
# systemdのユニットを`lib/systemd/system`へ同梱する。
# 使う側は`systemd.packages`へこのパッケージを渡して、
# `wantedBy`と、既定と違う値だけを`systemd.services`で足す。
# `nixos/host/bullet/comfyui/idle-free-memory.nix`がコンテナの中でそうしている。
{
  lib,
  haskell,
  haskellPackages,
  writeText,
  himari-src,
}:
let
  packages = haskellPackages.extend (
    hself: _hsuper: {
      # himariはstableのnixpkgsではbrokenなので、上流のソースから組む。
      himari = hself.callCabal2nix "himari" himari-src { };
    }
  );
  # 動かすものだけをstoreへ入れる。
  # ディレクトリをそのまま渡すと`dist-newstyle`のような作業中のファイルまで付いてくる。
  source = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./comfyui-idle-free-memory.cabal
      ./app
      ./src
      ./test
    ];
  };
  package = packages.callCabal2nix "comfyui-idle-free-memory" source { };
  hardening = import ../../lib/systemd-hardening.nix;
  # 同梱するユニット。
  # `ExecStart`の`@out@`は、インストールする時にこのパッケージ自身のパスへ置き換える。
  unit = writeText "comfyui-idle-free-memory.service" (
    lib.generators.toINI { listsAsDuplicateKeys = true; } {
      Unit = {
        Description = "Free ComfyUI memory while idle";
        After = "comfyui.service";
        # 依存関係で縛らない。
        # ComfyUIが落ちている間はHTTPが失敗するだけで、
        # プログラムはそれを記録して次の周回へ進む。
        # 縛って止めるより、動いていない相手を叩き続けて勝手に復帰する方が単純である。
      };
      Service = hardening.network // {
        ExecStart = "@out@/bin/comfyui-idle-free-memory";
        DynamicUser = true;
        Environment = [
          # 渡すのはホストとポートだけにして、スキームはプログラムの側で固定する。
          # comfy-workflowの`COMFYUI_AUTHORITY`と同じ形に揃える。
          # 既定は同じマシンで動くComfyUIの既定のポート。
          "COMFYUI_AUTHORITY=[::1]:8188"
          # 確認の間隔。
          # 活動時刻はComfyUI自身の記録から取るので、
          # 間隔を詰めても取りこぼしは減らない。
          # 解放が実際に走るのが最後の活動から`IDLE_SECONDS`後ちょうどではなく、
          # そこから最大でこの秒数だけ遅れる、という意味しか持たない。
          "POLL_INTERVAL_SECONDS=300"
          # これだけ何もしていなければ解放する。
          # 短くすると、少し考えてから次の生成を回す間に降ろされて載せ直しになる。
          "IDLE_SECONDS=600"
        ];
        # 待ち続けるのが仕事なので、終了は全て異常である。
        #
        # HTTPの失敗はプログラムが周回の中で吸収するので、
        # ここまで来る終了は環境変数の欠落や不正な値、プログラム自体の不具合など、
        # 待っても直らないものが基本になる。
        # 10秒固定のままだと、
        # systemdの既定の起動レート制限(10秒に5回)に掛からないため、
        # 直らない状態で10秒間隔の再起動を永久に繰り返す。
        #
        # `lib/container-socket-activation.nix`が`comfyui-proxy`へ入れているものと同じ、
        # nixpkgsの`ollama-model-loader`由来の指数バックオフで抑える。
        Restart = "always";
        RestartSec = "10s";
        RestartMaxDelaySec = "2h";
        RestartSteps = 10;
      };
      Install.WantedBy = "multi-user.target";
    }
  );
in
lib.pipe package [
  # コンテナの閉包へGHCを持ち込まない。
  haskell.lib.compose.justStaticExecutables
  # `justStaticExecutables`は`postFixup`で`$out/lib`を丸ごと消すので、
  # ユニットはその後に置く。
  (haskell.lib.compose.overrideCabal (old: {
    postFixup = (old.postFixup or "") + ''
      install -D -m 444 ${unit} "$out/lib/systemd/system/comfyui-idle-free-memory.service"
      substituteInPlace "$out/lib/systemd/system/comfyui-idle-free-memory.service" \
        --replace-fail @out@ "$out"
    '';
  }))
]
