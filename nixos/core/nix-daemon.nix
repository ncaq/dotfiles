{ config, inputs, ... }:
{
  # 現在デプロイされている構成を、編集可能な作業ツリーに依存せず再評価できるようにします。
  environment.etc."nixos-flake".source = inputs.self.outPath;

  nix = {
    settings = {
      experimental-features = [
        "flakes"
        "nix-command"
      ];
      substituters = [
        "https://cache.nixos.org/"
        "https://niks3-public.ncaq.net/"
        # niks3はnix-cache-infoにPriority 30をハードコードしており、
        # niks3-publicと同値で優先順位が決まりません。
        # tailnet経由のniks3-privateの方が高速なため、
        # `?priority`で明示的にpublicより高優先(数値が小さいほど高優先)にします。
        "https://seminar.border-saurolophus.ts.net:8443/niks3/private/?priority=20"
        "https://ncaq.cachix.org/"
        "https://nix-community.cachix.org/"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "niks3-public.ncaq.net-1:e/B9GomqDchMBmx3IW/TMQDF8sjUCQzEofKhpehXl04="
        "niks3-private.ncaq.net-1:YWkzGum1FwpNpWndvuWOrTFCFtDRAYLWFCeH9h78/u0="
        "ncaq.cachix.org-1:XF346GXI2n77SB5Yzqwhdfo7r0nFcZBaHsiiMOEljiE="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      cores = 0; # `make -j$NIX_BUILD_CORES`のようにコンパイルの並列度に使われます。0だと全コア。
      max-jobs = 3; # Nixが同時に実行するビルド(derivation)の数。
      accept-flake-config = true;
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
    gc = {
      automatic = true;
      dates = "Mon *-*-* 12:30:00";
    };
    optimise = {
      automatic = true;
      dates = "Fri *-*-* 12:30:00";
    };
    # nix-daemonにGitHubのアクセストークンを渡します。
    # `nix profile add`などを実行した際のGitHubのAPI rate limitを回避するために有用です。
    # `access-tokens`はクライアントからdaemonに転送されない設定のため、
    # 直接設定する必要があります。
    # nix-daemonはホスト全体で共有されるため、
    # このトークンは全ユーザのビルドに適用されます。
    # 本当は構造化された`access-tokens`フィールドを使いたいけれど、
    # sopsのファイルをパスで読み込ませる方法が分からないため、
    # nix.confのフラグメントをsopsで生成して読み込む方法で回避します。
    # 関連: [Specify access token via file · Issue #6536 · NixOS/nix](https://github.com/NixOS/nix/issues/6536)
    extraOptions = ''
      !include ${config.sops.templates."github-nix-avoid-rate-limit-token.conf".path}
    '';
  };

  # fixed-output derivationのビルド環境にHugging Faceのトークンを渡します。
  # `lib/fetch-hugging-face.nix`が`impureEnvVars`で受け取ります。
  # Hugging Faceのレート制限は匿名だとIPアドレス単位でしか枠が無いため、
  # 多数のモデルをまとめて取得すると429で待たされます。
  # 認証するとアカウント単位の枠になり、
  # 制限の値自体も上がります。
  # `-`を付けてシークレットがまだ配置されていなくても起動できるようにします。
  # nix-daemonはブート直後から必要になる一方、
  # sopsの復号はgpg-vaultの起動を待つためです。
  # トークンが無くても公開リポジトリのダウンロードは成功します。
  # なおトークンを更新した場合は、
  # nix-daemonを再起動するまで古い値が使われ続けます。
  # `restartUnits`で自動再起動させると、
  # `nixos-rebuild`の最中にそれ自身が使っているdaemonを落としてしまうため設定しません。
  systemd.services.nix-daemon.serviceConfig.EnvironmentFile = "-${
    config.sops.templates."nix-daemon-huggingface-token.env".path
  }";

  sops = {
    # nix.confのfragmentを生成することでクライアント側にも読める設定ファイルにします。
    # 自分のアカウントだけのFine-grained personal access tokensで、
    # Fine-grainedの最小限の権限であるPublic Repository権限だけを持ちます。
    # なので万が一漏れても大した問題はないので、
    # 権限は緩めで問題ありません。
    templates."github-nix-avoid-rate-limit-token.conf" = {
      content = ''
        access-tokens = github.com=${config.sops.placeholder."github-nix-avoid-rate-limit-token"}
      '';
      owner = "root";
      group = "wheel"; # 信頼できるとしたユーザも読めるようにしておきます。
      mode = "0440"; # グループ所属のユーザも読み取れます。
    };
    # nix-daemonのsystemdサービスに読ませる環境変数ファイルです。
    templates."nix-daemon-huggingface-token.env" = {
      content = ''
        HF_TOKEN=${config.sops.placeholder."huggingface/read-only"}
      '';
      owner = "root";
      group = "root";
      mode = "0400";
    };
    secrets = {
      # 最小権限の権限で`access-tokens`を設定します。
      # こちらはtemplatesが作れれば良いため、
      # rootさえ読めれば問題ありません。
      "github-nix-avoid-rate-limit-token" = {
        sopsFile = ../../secrets/github-nix-avoid-rate-limit.yaml;
        key = "nix-avoid-rate-limit";
        owner = "root";
        group = "root";
        mode = "0400";
      };
      # `impureEnvVars`で受け取ったトークンは、
      # 同じ変数名を指定した任意のfixed-output derivationから読めます。
      # ダウンロードにしか使わないのでread-onlyのトークンを渡します。
      "huggingface/read-only" = {
        sopsFile = ../../secrets/huggingface.yaml;
        key = "token/read-only";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };
}
