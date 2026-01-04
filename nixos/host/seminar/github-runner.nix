{ config, pkgs, ... }:
{
  # GitHub Actions self-hosted runner configuration
  #
  # Setup instructions:
  # 1. Generate a GitHub Personal Access Token (PAT) with appropriate permissions:
  #
  #    RECOMMENDED: Fine-grained Personal Access Token (より安全でスコープが限定的)
  #      - Organization permissions > Self-hosted runners: Read and Write
  #      - Organization permissions > Administration: Read (必須だがドキュメントには記載なし)
  #      - 有効期限を設定可能
  #
  #    OR Classic Personal Access Token (レガシー、広範な権限が必要)
  #      - For organization-wide runners: "admin:org" scope (組織全体の管理権限)
  #      - For repository-specific runners: "repo" scope
  #
  # 2. Create the token file:
  #    sudo mkdir -p /var/lib/secrets
  #    echo -n "YOUR_TOKEN_HERE" | sudo tee /var/lib/secrets/github-runner-token
  #    sudo chmod 600 /var/lib/secrets/github-runner-token
  #
  #    Note: このリポジトリではsops-nixなどの暗号化ツールは使っていないため、
  #    手動でのトークンファイル作成が標準的な方法です(atticd.envやcloudflared certと同様)
  #
  # 3. Set the repository or organization URL below
  # 4. Rebuild the system configuration

  services.github-runners = {
    # Runner name - can be customized
    seminar = {
      enable = true;

      # IMPORTANT: Set this to your GitHub repository or organization URL
      #
      # 組織レベルで登録すれば、その組織内の全リポジトリで汎用的に使えます:
      #   url = "https://github.com/your-organization";
      #
      # リポジトリ単位での登録:
      #   url = "https://github.com/username/repository";
      #
      url = builtins.throw "Please set the GitHub repository or organization URL in github-runner.nix";

      # Path to the file containing the GitHub token
      # The file should contain only the token with no trailing newline
      tokenFile = "/var/lib/secrets/github-runner-token";

      # Runner name (defaults to hostname if not specified)
      name = "seminar";

      # Additional labels for the runner
      extraLabels = [
        "nixos"
        "self-hosted"
      ];

      # Replace mode: 同名のランナーが既に登録されている場合、
      # それを削除してから新規登録します。
      # システムの再構築時にランナーを再登録する際に便利です。
      replace = true;

      # Ephemeral mode: runner will be removed after each job
      # This is more secure and recommended for untrusted workloads
      ephemeral = false;

      # Additional packages available to the runner
      # GitHub公式ホストランナーには100以上のツールがプリインストールされていますが、
      # ここでは実用的によく使われるツールを選定しています。
      # 参考: https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md
      extraPackages = with pkgs; [
        # Core utilities
        bash
        coreutils
        curl
        wget
        jq
        yq-go
        git
        git-lfs
        gnutar
        gzip
        xz
        zip
        unzip

        # Nix tools
        nix
        cachix

        # Build tools
        gnumake
        cmake
        gcc
        pkg-config

        # Container & DevOps
        docker
        docker-compose
        kubectl
        helm

        # Language runtimes (追加が必要な場合はここに記載)
        # nodejs # Node.jsが必要な場合
        # python3 # Pythonが必要な場合
        # go # Goが必要な場合

        # Cloud CLIs (必要に応じてコメント解除)
        # awscli2 # AWS CLI
        # google-cloud-sdk # Google Cloud CLI
        # azure-cli # Azure CLI

        # その他の便利ツール
        openssh
        rsync
        which
        findutils
        gnugrep
        gnused
        gawk
      ];

      # Service overrides for additional security or customization
      serviceOverrides = {
        # Uncomment to restrict network access
        # PrivateNetwork = false;

        # Additional systemd hardening options can be added here
        # See: https://www.freedesktop.org/software/systemd/man/systemd.exec.html
      };
    };
  };

  # Ensure Nix is available for the runner
  nix.settings = {
    # Allow the runner to use Nix
    allowed-users = [ "github-runner-seminar" ];
  };
}
