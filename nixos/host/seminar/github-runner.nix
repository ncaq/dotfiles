{ config, pkgs, ... }:
{
  # GitHub Actions self-hosted runner configuration
  #
  # Setup instructions:
  # 1. Generate a GitHub Personal Access Token (PAT) with appropriate permissions:
  #    - For organization-wide runners: "admin:org" scope
  #    - For repository-specific runners: "repo" scope
  #    - Or use a fine-grained PAT with read/write access to "Administration" resources
  #
  # 2. Create the token file:
  #    sudo mkdir -p /var/lib/secrets
  #    echo -n "YOUR_TOKEN_HERE" | sudo tee /var/lib/secrets/github-runner-token
  #    sudo chmod 600 /var/lib/secrets/github-runner-token
  #
  # 3. Set the repository URL below
  # 4. Rebuild the system configuration

  services.github-runners = {
    # Runner name - can be customized
    seminar = {
      enable = true;

      # IMPORTANT: Set this to your GitHub repository or organization URL
      # Examples:
      #   - Repository: "https://github.com/username/repository"
      #   - Organization: "https://github.com/organization"
      # url = "https://github.com/your-username/your-repo";
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

      # Replace existing runner with the same name
      replace = true;

      # Ephemeral mode: runner will be removed after each job
      # This is more secure and recommended for untrusted workloads
      ephemeral = false;

      # Additional packages available to the runner
      # Add any packages that your workflows need
      extraPackages = with pkgs; [
        bash
        coreutils
        curl
        git
        gnutar
        gzip
        nix
        xz
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
