/**
  `libgamemodeauto.so`が`dlopen`で`libgamemode.so`を見つけられるように、
  自身のlibディレクトリをRUNPATHへ追加するoverlay。

  `libgamemodeauto.so`は`LD_PRELOAD`されると、
  コンストラクタで`libgamemode.so`を`dlopen`してgamemodedへ登録を行う。
  この`dlopen`はライブラリ名だけで呼ばれるため、
  呼び出し元である`libgamemodeauto.so`自身のRUNPATHか、
  `LD_LIBRARY_PATH`などの検索パスに`libgamemode.so`が無いと失敗する。

  nixpkgsのgamemodeはRUNPATHにglibcしか持たせていないので、
  LutrisがProton(umu)経由でゲームを起動する時のように、
  pressure-vesselコンテナ内で検索パスがリセットされる環境では、

  ```
  gamemodeauto: dlopen failed - libgamemode.so: cannot open shared object file
  ```

  というエラーになりgamemodeが有効化されない。
  コンテナ内にも`/nix/store`は共有されているため、
  RUNPATHでstoreパスを直接指せば解決する。

  nixpkgsは同じ理由で`gamemoded`などのバイナリにはrpathを追加済みなので、
  ライブラリにも同じ措置をするだけであり、
  upstreamのnixpkgsでも修正されるべきパッケージングバグ。
*/
_final: prev: {
  gamemode = prev.gamemode.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      patchelf --add-rpath "$lib/lib" "$lib/lib/libgamemodeauto.so.0.0.0"
    '';
  });
}
