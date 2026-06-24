# ハードウェア情報

簡単なハードウェアの情報を記載します。

取得した日の結果なので、
時間が経つと情報が古くなります。
特にディスクの利用サイズなどは日々変動します。
過信はしてはいけません。

## PC

以下のコマンドでほぼ同じ最新の情報を取得できます。

```console
nix run "$HOME/dotfiles#fastfetch" -- --config "$HOME/dotfiles/home/prompt/environment/fastfetch-hardware.json"|perl -pe 's/^/- /'
```

fastfetchはメモリなどの容量をGiB単位で表示します。
GB単位と混同しないでください。

fastfetchの機能でGB単位系で表示させようとすると管理領域なども含むので合わせるのは困難です。

### デスクトップ

#### bullet, pristine, SSD0086

デスクトップです。
自作組み立てです。

3つの2TBのNVMe SSDを刺していて、
それぞれ個別のOSがブートしています。

- SN8100: bullet: NixOSネイティブブート環境
- SN850X: pristine: Windows Game
- SN850: SSD0086: Windows Work

と割り振られています。

この実行結果は便宜上bulletホスト上のものです。

- ncaq@bullet
- Core Software
- OS: NixOS 26.05 (Yarara) x86_64
- Kernel: Linux 6.18.35-xanmod1
- BIOS (UEFI): 1.A65 (5.35)
- Bootmgr: NixOS-efi - grubx64.efi
- Init System: systemd 260.2
- LM: lightdm-autologin 1.32.0 (X11)
- Shell: zsh 5.9.1
- WM: hm-xsession (X11)
- Terminal: tmux 3.6a
- Locale: ja_JP.UTF-8
- Core Hardware
- Host: MS-7E51 (1.0)
- Board: MAG X870 TOMAHAWK WIFI (MS-7E51) (1.0)
- TPM: TPM 2.0 Device
- Computing
- CPU: AMD Ryzen 9 9950X3D (32) @ 5.76 GHz
- GPU: NVIDIA GeForce RTX 5090 [Discrete]
- Vulkan: 1.4.329 - NVIDIA [595.71.05]
- OpenGL: 4.6.0 NVIDIA 595.71.05
- OpenCL: 3.0 CUDA 13.2.82
- Memory: 93.85 GiB
- Swap: 8.00 GiB
- Disk (/): 474.61 GiB / 1.82 TiB (26%) - btrfs
- Output
- Display (AW2725Q): 3840x2160 @ 1.5x in 27", 144 Hz [External] \*
- Display (LG HDR 4K): 3840x2160 @ 1.5x in 27", 60 Hz [External]
- Display (Acer VG270K): 3840x2160 @ 1.5x in 27", 60 Hz [External]
- Display (GSM5BBF): 3840x2160 @ 1.5x in 27", 144 Hz [External]
- Sound: USB Audio Speakers (40%)
- Input
- Keyboard 1: Topre REALFORCE 87 US
- Keyboard 2: Topre REALFORCE 87 US Keyboard
- Keyboard 3: Yubico YubiKey OTP+FIDO+CCID
- Keyboard 4: Logitech MX Ergo
- Mouse 1: Logitech MX Ergo
- Mouse 2: py-evdev-uinput
- Camera: HD Pro Webcam C920 - sRGB (640x480 px)

### ラップトップ

#### creep

ラップトップです。
[ThinkPad P16s Gen 2](https://www.lenovo.com/jp/ja/p/laptops/thinkpad/thinkpad-p-series/thinkpad-p16s-gen-2-16-inch-amd-mobile-workstation/len101t0075)
です。

ThinkPadですが組み込みの指紋センサーはありません。
代わりにYubiKey Bioを差し込んで、
FIDO認証としてディスクの復号化やパスキーなどに使っています。

- ncaq@creep
- Core Software
- OS: NixOS 26.05 (Yarara) x86_64
- Kernel: Linux 6.18.35-xanmod1
- BIOS (UEFI): R2FET63W (1.43 ) (1.43)
- Bootmgr: Linux Boot Manager - systemd-bootx64.efi
- Init System: systemd 260.2
- LM: lightdm-autologin 1.32.0 (X11)
- Shell: zsh 5.9.1
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
- Vulkan: 1.4.348 - radv [Mesa 26.1.2]
- OpenGL: 4.6 (Compatibility Profile) Mesa 26.1.2
- Memory: 27.11 GiB
- Swap: 4.07 GiB
- Disk (/): 202.90 GiB / 691.91 GiB (29%) - btrfs
- Output
- Display (LEN41B5): 1920x1200 in 16", 60 Hz [Built-in]
- Brightness (LEN41B5): 100% [Built-in]
- Input
- Keyboard 1: AT Translated Set 2 keyboard
- Keyboard 2: Logitech MX Ergo
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
- OS: NixOS 26.05 (Yarara) x86_64
- Kernel: Linux 6.18.34-xanmod1
- BIOS (UEFI): 3.30 (5.35)
- Bootmgr: UEFI OS - BOOTX64.EFI
- Init System: systemd 260.1
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
- Vulkan: 1.4.348 - radv [Mesa 26.1.1]
- OpenGL: 4.6 (Compatibility Profile) Mesa 26.1.1
- Memory: 61.89 GiB
- Swap: 72.00 GiB
- Disk (/): 461.66 GiB / 929.51 GiB (50%) - btrfs
- Disk (/mnt/noa): 2.69 TiB / 12.73 TiB (21%) - btrfs
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
