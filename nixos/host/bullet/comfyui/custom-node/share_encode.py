# ロスレスで保存した動画の隣へ、配布向けに圧縮した動画を作るモジュール。
#
# ロスレス動画は公開したり人へ渡したりするには大きすぎるので、
# そのまま出せる大きさの版も一緒に欲しい。
# 元のロスレスも残したいため、同じディレクトリへ拡張子だけ変えて並べる。
#
# 保存が終わった後にバックグラウンドのスレッドでffmpegを回す。
# 生成自体は既に成功しているので、
# 圧縮に失敗してもワークフローは成功のままにしてログだけ残す。
# 完成前のファイルをSamba越しに掴まないよう、
# `.partial`付きの名前へ書いてから`os.replace`で確定させる。
#
# 各カスタムノードのパッケージへsymlinkJoinで同じファイルを配り、
# `from .share_encode import start_share_encode`と相対importで使う。
import logging
import os
import subprocess
import threading
from pathlib import Path

logger = logging.getLogger(__name__)

# 配布用動画の拡張子。
# ロスレス側から`lossless.`が落ちただけの対になる名前にして、
# ファイル名を見ただけでどちらがどちらか分かるようにする。
share_suffix = ".av1.webm"
# 配布用の品質。
# 1104x848の5秒のロスレス出力で測ったところ、
# CRF 24で1.51MB(PSNR-Y 45.4dB)、30で0.97MB(43.6dB)、40で0.48MB(40.4dB)だった。
# 30ならロスレスの1/46でPSNR-Yは40dB台を保つので、配布する品質として十分。
share_crf = 30
# SVT-AV1のpreset。
# 2134x3840の5秒(104MB)をCRF 30で圧縮した時の実測。
#
#   preset 6:   5.5秒  3.73MB
#   preset 4:   7.8秒  3.37MB
#   preset 3:  14.2秒  3.28MB
#   preset 2:  25.0秒  3.06MB
#   preset 1:  48.3秒  2.99MB
#   preset 0: 103.3秒  2.96MB
#
# 1段下げるたびに時間はほぼ倍になるが、サイズの減りは2→1で2.2%、1→0で0.9%と潰れる。
# preset 2はpreset 0まで詰めた場合の圧縮の87%を4分の1の時間で得られる。
#
# 動画生成やアップスケール自体が数十分から数時間かかるのに対して、
# ここでの数十秒は誤差なので、速度より圧縮率を優先して選んでいる。
#
# なおここで作る版はそのまま公開に使っても困らない程度ではある。
# 画質を真剣に詰めたい時だけ、ロスレスからCRFを30より下げて画質を優先し、
# preset 0で時間をかけてエンコードし直せばよい。
share_preset = 2

# 圧縮を直列化するロック。
# 続けて生成すると複数のffmpegが並ぶが、
# コンテナのCPUQuotaは共有なので並べても総時間は縮まず、生成の邪魔になるだけ。
encode_lock = threading.Lock()


def start_share_encode(source: Path, video_suffix: str) -> None:
    """`source`から配布用の圧縮動画を作る作業を開始する。

    `video_suffix`は`source`が持つ拡張子で、
    これを`share_suffix`へ置き換えた名前が出力先になる。
    """
    destination = source.with_name(
        f"{source.name.removesuffix(video_suffix)}{share_suffix}"
    )
    threading.Thread(
        target=encode_for_share,
        args=(source, destination),
        name=f"share-encode-{destination.name}",
        daemon=True,
    ).start()


def encode_for_share(source: Path, destination: Path) -> None:
    # niceはLinuxではスレッド単位の属性で、子プロセスは生成元スレッドの値を継ぐ。
    # このスレッドだけを譲る側へ回して、ffmpegが生成のCPUを奪わないようにする。
    os.nice(19)
    partial = destination.with_name(
        f"{destination.name.removesuffix(share_suffix)}.partial{share_suffix}"
    )
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        # サービスから起動するので端末は無く、入力待ちで止まらないようにする。
        "-nostdin",
        # 中断した過去の実行が残した`.partial`をそのまま上書きする。
        "-y",
        "-i",
        os.fspath(source),
        "-c:v",
        "libsvtav1",
        "-crf",
        str(share_crf),
        "-preset",
        str(share_preset),
        # 入力が10-bitなので、8-bitへ落とすと単に情報が減るだけになる。
        # AV1はMain profileが10-bitを含むので再生互換の心配もない。
        "-pix_fmt",
        "yuv420p10le",
        # tuneは`0 = VQ, 1 = PSNR, 2 = SSIM`で既定は1。
        # 人が見るための動画なので、指標ではなく視覚品質を狙う0を選ぶ。
        # ただし視覚品質は主観なので、PSNRやSSIMでの裏付けは取っていない。
        "-svtav1-params",
        "tune=0",
        # 音声は雑に決めた値で、特に比較検討はしていない。
        # そもそも音声を持つ出力が少なく、容量はほぼ映像で決まるので、
        # Opusで十分とよく言われる128kbpsをそのまま使っている。
        "-c:a",
        "libopus",
        "-b:a",
        "128k",
        os.fspath(partial),
    ]
    try:
        with encode_lock:
            if destination.exists():
                logger.info(
                    "Skipping share encode because it already exists: %s", destination
                )
                return
            logger.info("Encoding video for sharing: %s", " ".join(command))
            subprocess.run(command, check=True)
            os.replace(partial, destination)
        logger.info("Encoded video for sharing: %s", destination)
    except Exception as error:
        # ロスレス側の保存は終わっているので、ここで失敗しても生成はやり直させない。
        logger.warning("Failed to encode video for sharing: %s: %s", destination, error)
        partial.unlink(missing_ok=True)
