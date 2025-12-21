# ハードウェア情報

## PC

書いた時に取得したものなので過信しないでください。
特にディスクの利用サイズなどは日々変動します。

```console
nix run --file '<nixpkgs>' fastfetch -- --logo none
```

コマンドを動いているマシンで実行することでほぼ同じ最新の情報を取得できます。

### デスクトップ

#### bullet, pristine, SSD0086

メインのデスクトップPCの簡単なハードウェアの情報は以下の通りです。

- Host: MS-7E51 (1.0)
- Display (AW2725Q): 3840x2160 @ 1.5x in 27", 144 Hz [External]
- Display (LG HDR 4K): 3840x2160 @ 1.5x in 27", 60 Hz [External]
- Display (Acer VG270K): 3840x2160 @ 1.5x in 27", 60 Hz [External]
- Display (GSM5BBF): 3840x2160 @ 1.5x in 27", 144 Hz [External]
- CPU: AMD Ryzen 9 9950X3D (32) @ 5.75 GHz
- GPU: NVIDIA GeForce RTX 5090 [Discrete]
- Memory: 96 GB
- Swap: 50 GiB
- Disk (/): 474.76 GiB / 1.82 TiB (26%)

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

- Host: A620M-HDV/M.2+
- CPU: AMD Ryzen 5 7600 (12) @ 5.17 GHz
- GPU: AMD Raphael [Integrated]
- Memory: 64 GB
- Swap: 34 GiB
- Disk (/): 144.04 GiB / 929.51 GiB (15%) - btrfs
- Disk (/mnt/noa): 608.59 GiB / 12.73 TiB (5%) - btrfs

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
