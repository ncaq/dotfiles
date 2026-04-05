{ pkgs, username, ... }:
{
  users = {
    # ユーザを宣言的に管理してインストールごとに情報を上書きします。
    mutableUsers = false;
    users = {
      # 通常利用するユーザです。
      ${username} = {
        isNormalUser = true;
        uid = 1000;
        extraGroups = [
          "input"
          "networkmanager"
          "pipewire"
          "uinput"
          "wheel"
        ];
        shell = pkgs.zsh;
        # `hashedPassword`をリポジトリにコミットしている理由:
        # yescrypt($y$)はメモリハード関数であり、
        # 高性能GPUでも数千hash/sec程度の速度しか出ません。
        # 十分なエントロピーのパスワードと組み合わせることで、
        # オフラインでのブルートフォース攻撃は計算量的に非現実的となります。
        #
        # 十分なエントロピーのパスワードを設定することは容易です。
        #
        # デスクトップPCは私を自宅でハンマーで脅す方が楽なのでオートログインに全任せして問題ありません。
        #
        # 外で人に触られる危険のあるラップトップPCは、
        # 指紋のFIDO2認証でパスワードをスキップできるようにしています。
        # よって長いパスワードにしても問題ありません。
        #
        # サーバはsshは公開鍵認証のみに設定しているため、
        # 緊急時に直接ログインする場合ぐらいにしかパスワードは必要ありません。
        # その時もYubiKey Bioをこちらにも設定しているため、
        # 差し込んで指紋認証すればパスワード入力はスキップできます。
        #
        # sops-nixで暗号化する選択肢もありますが、
        # 初回nixos-install時にsops-nixのsystemdサービスが未起動で、
        # シークレットが展開されないブートストラップ問題があり、
        # 運用の複雑さに対してセキュリティ上のゲインが小さいためハッシュ値をコミットしています。
        hashedPassword = "$y$j9T$wU3N0Q3P9fHGrMso8Z22k/$FQ8NgFVzUgo5c1RYWp/BAuRBioPUj7CAiwBm/paRf1B";
      };
      root = {
        # rootユーザのパスワードを使うことは滅多にありません。
        # レスキューモードもNixOSでは世代管理で後ろの正常な世代に戻れるためあまり出番がありません。
        # レスキューモードを使う場合でもカーネルパラメータに`init=/bin/sh`を指定すれば、
        # ディスクさえ復号化できればパスワード入力はスキップできます。
        # しかし念の為にログインできる余地を残しておきます。
        hashedPassword = "$y$j9T$Pe0nKS1opi71jOuppQo0p/$zB9VQoagiIHgvnGNBgyxmBk7Ib6xyMDsfwW451pZoaC";
      };
    };
  };
}
