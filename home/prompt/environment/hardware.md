# ハードウェア情報

簡単なハードウェアの情報を記載します。

取得した日の結果なので、
時間が経つと情報が古くなります。
特にディスクの利用サイズなどは日々変動します。
過信はしてはいけません。

## PC

以下のコマンドでほぼ同じ最新の情報を取得できます。

```console
nix run "$HOME/dotfiles#fastfetch" -- --config "$HOME/dotfiles/home/prompt/environment/fastfetch-hardware.json"
```

fastfetchはメモリなどの容量をGiB単位で表示します。
GB単位と混同しないでください。

fastfetchの機能でGB単位系で表示させようとすると管理領域なども含むので合わせるのは困難です。

### デスクトップ

#### bullet, pristine, SSD0086

デスクトップです。
自作組み立てです。

3つのSSDを刺していて、
それぞれ個別のOSがブートしています。
この実行結果は便宜上bulletホスト上のものです。
SSDとソフトウェアスタック以外を共有するpristineとSSD0086もここに記載します。
いずれのOSも、
2TBのNVMe SSD(SN8100, SN850X, SN850)のうち一つにインストールされています。

- ncaq@bullet
- Core Software
- OS: NixOS 25.11 (Xantusia) x86_64
- Kernel: Linux 6.12.85
- BIOS (UEFI): 1.A65 (5.35)
- Bootmgr: NixOS-efi - grubx64.efi
- Init System: systemd 258.7
- LM: lightdm-autologin 1.32.0 (X11)
- Shell: zsh 5.9
- WM: hm-xsession (X11)
- Terminal: tmux 3.6a
- Locale: ja_JP.UTF-8
- Core Hardware
- Host: MS-7E51 (1.0)
- Board: MAG X870 TOMAHAWK WIFI (MS-7E51) (1.0)
- TPM: TPM 2.0 Device
- Computing
- CPU: AMD Ryzen 9 9950X3D (32) @ 5.75 GHz
- GPU: NVIDIA GeForce RTX 5090 [Discrete]
- Vulkan: 1.4.312 - NVIDIA [580.142]
- OpenGL: 4.6.0 NVIDIA 580.142
- OpenCL: 3.0 CUDA 13.0.97
- Memory: 93.85 GiB
- Swap: 8.00 GiB
- Disk (/): 390.36 GiB / 1.82 TiB (21%) - btrfs
- Output
- Display (AW2725Q): 3840x2160 @ 1.5x in 27", 144 Hz [External] \*
- Display (LG HDR 4K): 3840x2160 @ 1.5x in 27", 60 Hz [External]
- Display (Acer VG270K): 3840x2160 @ 1.5x in 27", 60 Hz [External]
- Display (GSM5BBF): 3840x2160 @ 1.5x in 27", 144 Hz [External]
- Sound: USB Audio Speakers (40%)
- Input
- Keyboard 1: Topre REALFORCE 87 US
- Keyboard 2: Topre REALFORCE 87 US Keyboard
- Mouse 1: Logitech MX Ergo
- Mouse 2: py-evdev-uinput
- Camera: HD Pro Webcam C920 - sRGB (640x480 px)

### ラップトップ

#### creep

ラップトップです。
[ThinkPad P16s Gen 2](https://www.lenovo.com/jp/ja/p/laptops/thinkpad/thinkpad-p-series/thinkpad-p16s-gen-2-16-inch-amd-mobile-workstation/len101t0075)です。

ThinkPadですが指紋センサーはありません。

- ncaq@creep
- Core Software
- OS: NixOS 25.11 (Xantusia) x86_64
- Kernel: Linux 6.12.85
- BIOS (UEFI): R2FET63W (1.43 ) (1.43)
- Bootmgr: Linux Boot Manager - systemd-bootx64.efi
- Init System: systemd 258.7
- LM: lightdm-autologin 1.32.0 (X11)
- Shell: zsh 5.9
- WM: hm-xsession (X11)
- Terminal: tmux 3.6a
- Locale: ja_JP.UTF-8
- Core Hardware
- Host: 21K9CTO1WW (ThinkPad P16s Gen 2)
- Board: 21K9CTO1WW (SDK0K17763 WIN)
- TPM: 2.0
- Computing
- CPU: AMD Ryzen 5 PRO 7540U (12) @ 4.98 GHz
- GPU: AMD Radeon 740M Graphics [Integrated]
- Vulkan: 1.4.318 - radv [Mesa 25.2.6]
- OpenGL: 4.6 (Compatibility Profile) Mesa 25.2.6
- Memory: 27.11 GiB
- Swap: 8.00 GiB
- Disk (/): 170.73 GiB / 691.91 GiB (25%) - btrfs
- Output
- Display (AUOD49C): 1920x1200 in 16", 60 Hz [Built-in]
- Brightness (AUOD49C): 100% [Built-in]
- Sound: Ryzen HD Audio Controller Speaker (40%)
- Input
- Keyboard: AT Translated Set 2 keyboard
- Mouse 1: py-evdev-uinput
- Mouse 2: ELAN0688:00 04F3:320B Touchpad
- Mouse 3: Logitech MX Ergo
- Mouse 4: TPPS/2 Elan TrackPoint
- Mouse 5: ELAN0688:00 04F3:320B Mouse
- Camera: Integrated Camera: Integrated C - sRGB (1280x720 px)

### サーバ

#### seminar

サーバ用PCです。
自作組み立てPCです。

- ncaq@seminar
- Core Software
- OS: NixOS 25.11 (Xantusia) x86_64
- Kernel: Linux 6.12.85
- BIOS (UEFI): 3.30 (5.35)
- Bootmgr: UEFI OS - BOOTX64.EFI
- Init System: systemd 258.7
- LM: sshd 10.3p1 (TTY)
- Shell: zsh 5.9
- Terminal: tmux 3.6a
- Locale: ja_JP.UTF-8
- Core Hardware
- Host: A620M-HDV/M.2+
- Board: A620M-HDV/M.2+
- TPM: TPM 2.0 Device
- Computing
- CPU: AMD Ryzen 5 7600 (12) @ 5.17 GHz
- GPU: AMD Raphael [Integrated]
- Vulkan: 1.4.318 - radv [Mesa 25.2.6]
- OpenGL: 4.6 (Compatibility Profile) Mesa 25.2.6
- Memory: 61.89 GiB
- Swap: 72.00 GiB
- Disk (/): 402.35 GiB / 929.51 GiB (43%) - btrfs
- Disk (/mnt/noa): 2.61 TiB / 12.73 TiB (20%) - btrfs
- Output
- Sound: Dummy Output (100%)
- Input

## スマートデバイス

### スマートフォン

#### paint

[Galaxy Z Fold7](https://www.samsung.com/jp/smartphones/galaxy-z-fold7/)

- Host: samsung SM-F966Q
- CPU: Qualcomm Snapdragon 8 Elite for Galaxy [SM8750] (8)
- GPU: Qualcomm Adreno (TM) 830 [Integrated]
- Memory: 16 GB
- Swap: 20.00 GiB
- Disk (/): 7.06 GiB / 7.06 GiB (100%) - erofs [Read-only]
- Disk (/storage/emulated): 114.81 GiB / 936.83 GiB (12%) - fuse

### タブレット

#### dream

[Galaxy Tab S9 Ultra](https://www.samsung.com/jp/tablets/galaxy-tab-s/galaxy-tab-s9-ultra-wi-fi-graphite-512gb-sm-x910nzaexjp/)

- Host: samsung SM-X910
- CPU: Qualcomm Snapdragon 8 Gen 2 for Galaxy [SM8550] (8)
- GPU: Qualcomm Adreno (TM) 740 [Integrated]
- Memory: 12 GB
- Swap: 12.00 GiB
- Disk (/): 6.50 GiB / 6.50 GiB (100%) - erofs [Read-only]
- Disk (/storage/emulated): 71.38 GiB / 462.07 GiB (15%) - fuse
