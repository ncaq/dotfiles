/**
  `linux_xanmod`をサーバ用途向けにチューニングし直したカーネルパッケージ。

  XanModはデスクトップ/低レイテンシ向けに振った設定を多く含むが、
  実際にmainlineデフォルトから外れていて、
  かつサーバ用途に向かない設定は限定的。

  サーバ用途に向かない少数の設定を無効化すれば、
  ハックしやすくメンテナンスされている便利なカーネルが手に入る。

  XanModの設定のサーバにも有益なものは当然そのまま残します。

  XanModのデスクトップ向け設定のうち、
  サーバでは意味がないようなものも、
  ビルドするだけで起動しないとか、
  バイナリサイズを多少増やす程度の無害なものはそのまま残します。

  CPUモデル固有の最適化は別の`cpu-optimized-kernel-overlay.nix`で適用するため、
  ここではCPU最適化のKconfigには触らない。

  このファイルは`callPackage`ではなく`import`で呼び出すこと。
  返り値である`linuxKernel.kernels.linux_xanmod.override`の結果は、
  `xanmod-kernels.nix`の引数を再上書きできる`.override`関数を露出している。
  `callPackage`で包むと外側の`makeOverridable`に隠されて、
  下流の`cpu-optimized-kernel-overlay.nix`が`kernelPatches`を、
  追加するための`.override`が機能しなくなる。
*/
{ lib, linuxKernel }:
linuxKernel.kernels.linux_xanmod.override (oldArgs: {
  kernelPatches = (oldArgs.kernelPatches or [ ]) ++ [
    {
      name = "xanmod-server-rcu";
      patch = null;
      structuredExtraConfig = with lib.kernel; {
        # プリエンプトされたRCUリーダの優先度ブースト。
        # リアルタイムカーネル向け機能で、非RTサーバには不要。
        # mainlineデフォルトは`PREEMPT_RT=y`の時のみ`y`、それ以外は`n`。
        RCU_BOOST = lib.mkForce no;
        # `RCU_BOOST_DELAY`はxanmodが`"0"`(即時ブースト)に設定しているが、
        # `RCU_BOOST=n`に依存するKconfigなので無効化される。
        # ただしxanmodの設定が`optional=false`(必須)のままだと、
        # nixpkgsの`generate-config.pl`が依存切れによるunused optionをエラー扱いするため、
        # `option`でoptional化(`?`付き)してwarning扱いに留める。
        # 値そのものはxanmod元の`"0"`をそのまま使う。
        # 依存切れで反映されないので何でも良い。
        RCU_BOOST_DELAY = lib.mkForce (option (freeform "0"));
        # `RCU_EXP_KTHREAD`: expedited grace periodをリアルタイムkthreadで実行。
        # `NR_CPUS=8192`の環境(nixpkgsデフォルト)ではmainlineは`n`。
        # `depends on RCU_BOOST && RCU_EXPERT`のため`RCU_BOOST=n`下では同様にoptional化が必要。
        RCU_EXP_KTHREAD = lib.mkForce (option no);
        # `RCU_DOUBLE_CHECK_CB_TIME`: コールバック時間チェック追加。
        # `depends on RCU_EXPERT`のみで`RCU_EXPERT=y`は満たされるためoptional化不要。
        # mainlineデフォルトは`n`。
        RCU_DOUBLE_CHECK_CB_TIME = lib.mkForce no;
      };
    }
  ];
})
