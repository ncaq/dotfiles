{
  pkgs,
  username,
  ...
}:
let
  # 通常のユーザのUID。
  # ほとんどのLinuxディストリビューションで、最初の通常ユーザはUID 1000から始まります。
  uid = 1000;
in
{
  users = {
    # ユーザを宣言的に管理してインストールごとに情報を上書きします。
    mutableUsers = false;
    users = {
      # 通常利用するユーザです。
      ${username} = {
        isNormalUser = true;
        inherit uid;
        extraGroups = [
          "networkmanager"
          "pipewire"
          "wheel"
        ];
        shell = pkgs.zsh;
        # `home-manager-${username}.service`はboot時に`multi-user.target`の段階で実行されます。
        # 内部で`gpg --edit-key`などgpg-agentに依存する処理を行います。
        # gpg-agentは`/run/user/$UID/`配下にソケットを作成するため、
        # `user@$UID.service`が起動していないとIPC接続に失敗します。
        # lingerを有効にしてログインしなくてもboot時から`user@$UID.service`を起動させ、
        # `After=user@.service`で順序を明示することでこの問題を回避します。
        linger = true;
        # `hashedPassword`をリポジトリにコミットしている理由:
        # yescrypt($y$)はメモリハード関数であり、
        # 高性能GPUでも数千hash/sec程度の速度しか出ません。
        # 十分なエントロピーのパスワードと組み合わせることで、
        # オフラインでのブルートフォース攻撃は計算量的に非現実的となります。
        #
        # 十分なエントロピーのパスワードを設定することは容易です。
        #
        # デスクトップPCは私を自宅でハンマーで脅す方が楽なので、
        # オートログインに全任せして問題ありません。
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
        hashedPassword = "$y$j9T$tE1NrBnAam.0Pht2Fom/T.$KTVpj704fIlSgbtVRnTi0P/1NvBPZErkMpX0q5EE5rA";
      };
      root = {
        # rootユーザのパスワードを使うことは滅多にありません。
        # レスキューモードもNixOSでは世代管理で後ろの正常な世代に戻れるためあまり出番がありません。
        # レスキューモードを使う場合でもカーネルパラメータに`init=/bin/sh`を指定すれば、
        # ディスクさえ復号化できればパスワード入力はスキップできます。
        # しかし念の為にログインできる余地を残しておきます。
        hashedPassword = "$y$j9T$E0S7CZxsl2bETtYr4vx9S1$nP5zPj7fOeJukGHeuoZTvWyi2ifwXSAnp9Glbqsq725";
      };
    };
  };
  # lingerだけでは`user@$UID.service`と`home-manager-${username}.service`が並列起動するため、
  # gpg-agentソケットの準備が間に合わずIPC接続に失敗することがあります。
  # `user@$UID.service`の起動完了を待つことで競合状態を防ぎます。
  systemd.services."home-manager-${username}" = {
    after = [ "user@${toString uid}.service" ];
    wants = [ "user@${toString uid}.service" ]; # 失敗してもなるべく起動してほしいので弱い依存。
  };
}
