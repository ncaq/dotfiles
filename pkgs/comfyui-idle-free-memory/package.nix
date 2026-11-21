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
  localHaskellPackages,
  runCommand,
  writeText,
}:
let
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
  mainProgram = "comfyui-idle-free-memory";
  executable = lib.pipe (localHaskellPackages.callCabal2nix mainProgram source { }) [
    # コンテナのクロージャへGHCを持ち込まない。
    haskell.lib.compose.justStaticExecutables
  ];
  hardening = import ../../lib/systemd-hardening.nix;
  # 同梱するユニット。
  unit = writeText "${mainProgram}.service" (
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
        ExecStart = lib.getExe executable;
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
  # 実行ファイルとは別のderivationで包んでユニットを足す。
  # Haskellのderivationの中に置くと、
  # ユニットやハードニングの設定を変えるだけでGHCのビルドとテストがやり直しになる。
  package =
    runCommand executable.name
      {
        inherit (executable) pname version;
        passthru.tests.unit = unitCheck;
        meta.mainProgram = mainProgram;
      }
      ''
        mkdir -p "$out/bin"
        ln -s ${lib.getExe executable} "$out/bin/${mainProgram}"
        install -D -m 444 ${unit} "$out/lib/systemd/system/${mainProgram}.service"
      '';
  # 同梱したユニットが、使う側の`systemd.packages`から読める形で入っていることを確かめる。
  #
  # ユニットが欠けても、使う側の構成は評価もビルドも通ってしまう。
  # NixOSは`systemd.services`に書いた`wantedBy`と`environment`だけから自前のユニットを作るので、
  # `ExecStart`の無いユニットになり、適用して初めて起動しないと分かる。
  unitCheck = runCommand "${mainProgram}-unit-check" { } ''
    unit=${package}/lib/systemd/system/${mainProgram}.service
    test -f "$unit"
    # `ExecStart`が指す先が実行できること。
    exec_start=$(grep -E '^ExecStart=' "$unit")
    test -x "''${exec_start#ExecStart=}"
    # `systemd-analyze verify`は走らせない。
    # ビルドのサンドボックスの中では`/run/systemd`を作れずに失敗する。
    touch "$out"
  '';
in
package
