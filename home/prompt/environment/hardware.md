# ハードウェア情報

## PC

取得した日の結果なので、
時間が経つと情報が古くなります。
特にディスクの利用サイズなどは日々変動します。
過信はしてはいけません。

以下のコマンドでほぼ同最新の情報を取得できます。

```console
nix run "$HOME/dotfiles#fastfetch" -- --config "$HOME/dotfiles/home/prompt/environment/fastfetch-hardware.json"
```

### デスクトップ

#### bullet, pristine, SSD0086

メインのデスクトップPCの簡単なハードウェアの情報は以下の通りです。
この結果は便宜上bulletホストで実行しています。
SSDとソフトウェアスタック以外を共有するpristineとSSD0086もここに記載します。

- ncaq@bullet
- -----------
- OS: NixOS 25.11 (Xantusia) x86_64
- Host: MS-7E51 (1.0)
- Kernel: Linux 6.12.74
- Shell: zsh 5.9
- Display (AW2725Q): 3840x2160 @ 1.5x in 27", 144 Hz [External] *
- Display (LG HDR 4K): 3840x2160 @ 1.5x in 27", 60 Hz [External]
- Display (Acer VG270K): 3840x2160 @ 1.5x in 27", 60 Hz [External]
- Display (GSM5BBF): 3840x2160 @ 1.5x in 27", 144 Hz [External]
- WM: hm-xsession (X11)
- Terminal: tmux 3.6a
- CPU: AMD Ryzen 9 9950X3D (32) @ 5.75 GHz
- GPU: NVIDIA GeForce RTX 5090 [Discrete]
- Memory: 93.85 GiB
- Swap: 50.92 GiB
- Disk (/): 501.34 GiB / 1.82 TiB (27%) - btrfs
- Locale: ja_JP.UTF-8

同じマザーボードにSSDを分けて3つ入っているいずれのOSも、
2TBのNVMe SSD(SN8100, SN850X, SN850)のうち一つにインストールされています。

### ラップトップ

#### creep

メインのラップトップPCであるThinkPad P16s Gen 2の簡単なハードウェアの情報は以下の通りです。

- Host: 21K9CTO1WW (ThinkPad P16s Gen 2)
- Display (AUOD49C): 1920x1200 in 16", 60 Hz [Built-in]
- CPU: AMD Ryzen 5 PRO 7540U (12) @ 4.98 GHz
- GPU: AMD Radeon 740M Graphics [Integrated]
- Memory: 32 GB
- Swap: 17.55 GiB
- Disk (/): 145.07 GiB / 691.91 GiB (21%) - btrfs

### サーバ

#### seminar

メインのサーバの簡単なハードウェアの情報は以下の通りです。

- ncaq@seminar
- ------------
- OS: NixOS 25.11 (Xantusia) x86_64
- Host: A620M-HDV/M.2+
- Kernel: Linux 6.12.70
- Shell: zsh 5.9
- Terminal: tmux 3.6a
- CPU: AMD Ryzen 5 7600 (12) @ 5.17 GHz
- GPU: AMD Raphael [Integrated]
- Memory: 61.89 GiB
- Swap: 34.95 GiB
- Disk (/): 403.14 GiB / 929.51 GiB (43%) - btrfs
- Disk (/mnt/noa): 2.45 TiB / 12.73 TiB (19%) - btrfs
- Locale: ja_JP.UTF-8

## スマートデバイス

### スマートフォン

#### Galaxy Z Fold7

メインのスマートフォンの簡単なハードウェアの情報は以下の通りです。

- Host: samsung SM-F966Q
- CPU: Qualcomm Snapdragon 8 Elite for Galaxy [SM8750] (8)
- GPU: Qualcomm Adreno (TM) 830 [Integrated]
- Memory: 16 GB
- Swap: 20.00 GiB
- Disk (/): 7.06 GiB / 7.06 GiB (100%) - erofs [Read-only]
- Disk (/storage/emulated): 114.81 GiB / 936.83 GiB (12%) - fuse

### タブレット

#### Galaxy Tab S9 Ultra

メインのタブレットの簡単なハードウェアの情報は以下の通りです。

- Host: samsung SM-X910
- CPU: Qualcomm Snapdragon 8 Gen 2 for Galaxy [SM8550] (8)
- GPU: Qualcomm Adreno (TM) 740 [Integrated]
- Memory: 12 GB
- Swap: 12.00 GiB
- Disk (/): 6.50 GiB / 6.50 GiB (100%) - erofs [Read-only]
- Disk (/storage/emulated): 71.38 GiB / 462.07 GiB (15%) - fuse
