# ハードウェア情報

簡単なハードウェアの情報を記載します。

取得した日の結果なので、
時間が経つと情報が古くなります。
特にディスクの利用サイズなどは日々変動します。
過信はしてはいけません。

## PC

以下のコマンドでほぼ同じ最新の情報を取得できます。

```console
nix run "$HOME/dotfiles#fastfetch" -- --config "$HOME/dotfiles/prompt/environment/fastfetch-hardware.json"|perl -pe 's/^/- /'
```

fastfetchはメモリなどの容量をGiB単位で表示します。
GB単位と混同しないでください。

fastfetchの機能でGB単位系で表示させようとすると管理領域なども含むので合わせるのは困難です。

### デスクトップ

#### bullet, pristine, SSD0086

デスクトップです。
自作組み立てです。

3つの2TBのNVMe SSDを挿していて、
それぞれ個別のOSがブートしています。

- SN8100: bullet: NixOSネイティブブート環境
- SN850X: pristine: Windows Game
- SN850: SSD0086: Windows Work

と割り振られています。

この実行結果は便宜上bulletホスト上のものです。

- ncaq@bullet
- Core Software
- OS: NixOS 26.05 (Yarara) x86_64
- Kernel: Linux 6.18.38-xanmod1
- BIOS (UEFI): 1.A92 (5.41)
- Bootmgr: Limine - BOOTX64.EFI
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
- Memory: 93.71 GiB
- Swap: 8.00 GiB
- Disk (/): 452.59 GiB / 1.82 TiB (24%) - btrfs
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
- Mouse 1: xremap
- Mouse 2: Logitech MX Ergo
- Camera: HD Pro Webcam C920 - sRGB (640x480 px)

### ラップトップ

#### creep

ラップトップです。
[ThinkPad P16s Gen 2](https://www.lenovo.com/jp/ja/p/laptops/thinkpad/thinkpad-p-series/thinkpad-p16s-gen-2-16-inch-amd-mobile-workstation/len101t0075)
です。

ThinkPadですが組み込みの指紋センサはありません。
代わりにYubiKey Bioを差し込んで、
FIDO認証としてディスクの復号化やパスキーなどに使っています。

- ncaq@creep
- Core Software
- OS: NixOS 26.05 (Yarara) x86_64
- Kernel: Linux 6.18.38-xanmod1
- BIOS (UEFI): R2FET69W (1.49 ) (1.49)
- Bootmgr: Limine - BOOTX64.EFI
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
- Vulkan: 1.4.354 - radv [Mesa 26.1.4]
- OpenGL: 4.6 (Compatibility Profile) Mesa 26.1.4
- Memory: 27.11 GiB
- Swap: 4.07 GiB
- Disk (/): 223.74 GiB / 691.91 GiB (32%) - btrfs
- Output
- Display (LEN41B5): 1920x1200 in 16", 60 Hz [Built-in]
- Brightness (LEN41B5): 100% [Built-in]
- Input
- Keyboard 1: AT Translated Set 2 keyboard
- Keyboard 2: Logitech MX Ergo
- Mouse 1: xremap
- Mouse 2: ELAN0688:00 04F3:320B Touchpad
- Mouse 3: Logitech MX Ergo
- Mouse 4: TPPS/2 Elan TrackPoint
- Mouse 5: ELAN0688:00 04F3:320B Mouse
- Camera: Integrated Camera: Integrated C - sRGB (1280x720 px)

### サーバ

#### seminar

サーバ用PCです。
自作組み立てPCです。

`/mnt/noa`のストレージシステムは、
複数のHDDをRAID 1構成にして束ねて、
それぞれbcacheでSN770 1TB SSDを共有のキャッシュとして使って、
高速かつ大容量のストレージシステムを構築しています。
耐障害の信頼性は低いですが、
自宅サーバであることの制約を考えてキャッシュは共有にしています。

- ncaq@seminar
- Core Software
- OS: NixOS 26.05 (Yarara) x86_64
- Kernel: Linux 6.18.38-xanmod1
- BIOS (UEFI): 4.21 (5.41)
- Bootmgr: Limine - BOOTX64.EFI
- Init System: systemd 260.2
- LM: sshd 10.3p1 (TTY)
- Shell: zsh 5.9.1
- Terminal: tmux 3.6a
- Locale: ja_JP.UTF-8
- Core Hardware
- Host: A620M-HDV/M.2+
- Board: A620M-HDV/M.2+
- TPM: TPM 2.0 Device
- Computing
- CPU: AMD Ryzen 5 7600 (12) @ 5.17 GHz
- GPU: AMD Raphael [Integrated]
- Vulkan: 1.4.354 - radv [Mesa 26.1.4]
- OpenGL: 4.6 (Compatibility Profile) Mesa 26.1.4
- Memory: 61.89 GiB
- Swap: 72.00 GiB
- Disk (/): 250.70 GiB / 1.82 TiB (13%) - btrfs
- Disk (/mnt/noa): 2.88 TiB / 12.73 TiB (23%) - btrfs
- Output
- Sound: Dummy Output (100%)
- Input

## スマートデバイス

USBデバッグを許可した端末をPCに繋いで以下のコマンドを実行すると、
adbを通してほぼ同じ最新の情報を取得できます。

```console
"$HOME/dotfiles/prompt/environment/android-fetch-hardware.hs"
```

`Memory`の`nominal`は、
見えているメモリの量から推定した製品としての公称の容量です。

### スマートフォン

#### paint

[Galaxy Z Fold7](https://www.samsung.com/jp/smartphones/galaxy-z-fold7/)

- Name: paint
- Product: Galaxy Z Fold7
- Host: samsung SM-F966Q
- OS: Android 17 (SDK 37), One UI 9.0
- Kernel: Linux 6.6.127-android15-8-p4a765df-abogkiF966QOPU1CZJD-4k
- CPU: Qualcomm Snapdragon 8 Elite for Galaxy [SM8750-AC] (8) 2x 4.47 GHz + 6x 3.53 GHz
- GPU: Qualcomm Adreno (TM) 830
- Memory: 14.74 GiB (nominal 16 GB)
- Swap: 20.00 GiB
- Disk (/data): 193.47 GiB / 936.20 GiB (21%) - f2fs
- Display 1: 1968x2184 in 8.0", 120 Hz
- Display 2: 1080x2520 in 6.5", 120 Hz
- Battery: 4400 mAh

### タブレット

#### lacquer

[Galaxy Tab S12 Ultra](https://www.samsung.com/jp/tablets/galaxy-tab-s/galaxy-tab-s12-ultra-gray-256gb-sm-x940nzaaxjp/)

- Name: lacquer
- Product: Galaxy Tab S12 Ultra
- Host: samsung SM-X940
- OS: Android 17 (SDK 37), One UI 9.0
- Kernel: Linux 6.12.69-android16-6-pe68bd8c-abogkiX940XXU2AZJA-4k
- CPU: MediaTek Dimensity 9500 [MT6993] (8) 1x 4.21 GHz + 3x 3.50 GHz + 4x 2.70 GHz
- GPU: ARM Mali-G1-Ultra MC12
- Memory: 15.10 GiB (nominal 16 GB)
- Swap: 20.00 GiB
- Disk (/data): 70.95 GiB / 938.25 GiB (8%) - f2fs
- Display: 1848x2960 in 14.6", 120 Hz
- Battery: 11600 mAh
