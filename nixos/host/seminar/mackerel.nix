{
  pkgs,
  lib,
  config,
  ...
}:
let
  # 分単位で指定する標準的なチェックの間隔。
  check_interval = 3;
in
{
  services.mackerel-agent = {
    enable = true;
    runAsRoot = true;
    apiKeyFile = config.sops.templates."mackerel-api-key.conf".path;
    settings = {
      # エージェント自身のメモリ使用量も収集
      diagnostic = true;
      # ファイルシステムをデバイス名(dm-1等)ではなくマウントポイント名で表示
      filesystems.use_mountpoint = true;
      # ヘルスチェックプラグイン
      plugin.checks = {
        ssh = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-ssh";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.netcat
              ];
              text = ''
                # SSH bannerを取得できればOK
                banner=$(timeout 2 bash -c 'echo "" | nc localhost 22' 2>&1 | head -1)
                if [[ "$banner" =~ ^SSH-2\.0 ]]; then
                  echo "SSH OK (banner: $banner)"
                  exit 0
                else
                  echo "SSH CRITICAL: no SSH banner received"
                  exit 2
                fi
              '';
            }
          );
          inherit check_interval;
        };
        tailscale = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-tailscale";
              runtimeInputs = [
                pkgs.jq
                pkgs.tailscale
              ];
              text = ''
                # BackendStateがRunningかつSelf.OnlineがtrueであればOK
                status=$(tailscale status --json 2>&1)
                backend_state=$(echo "$status" | jq -r '.BackendState' 2>/dev/null || echo "unknown")
                online=$(echo "$status" | jq -r '.Self.Online' 2>/dev/null || echo "false")
                if [[ "$backend_state" == "Running" ]] && [[ "$online" == "true" ]]; then
                  echo "Tailscale OK (connected to tailnet)"
                  exit 0
                else
                  echo "Tailscale CRITICAL: BackendState=$backend_state, Online=$online"
                  exit 2
                fi
              '';
            }
          );
          inherit check_interval;
        };
        cloudflared = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-cloudflared";
              runtimeInputs = [ pkgs.systemd ];
              text = ''
                if systemctl is-active --quiet cloudflared-tunnel-seminar.service; then
                  echo "Cloudflared OK"
                  exit 0
                else
                  echo "Cloudflared CRITICAL: service not running"
                  exit 2
                fi
              '';
            }
          );
          inherit check_interval;
        };
        caddy = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-caddy";
              runtimeInputs = [ pkgs.curl ];
              text = ''
                if curl -f -s http://127.0.0.1:8080 > /dev/null 2>&1; then
                  echo "Caddy OK"
                  exit 0
                else
                  echo "Caddy CRITICAL: HTTP check failed"
                  exit 2
                fi
              '';
            }
          );
          inherit check_interval;
        };
        samba = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-samba";
              runtimeInputs = [ pkgs.systemd ];
              text = ''
                if systemctl is-active --quiet samba-smbd.service; then
                  echo "Samba OK"
                  exit 0
                else
                  echo "Samba CRITICAL: service not running"
                  exit 2
                fi
              '';
            }
          );
          inherit check_interval;
        };
        postgresql = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-postgresql";
              runtimeInputs = [
                pkgs.postgresql
                pkgs.util-linux
              ];
              text = ''
                if runuser -u healthcheck -- psql -d healthcheck -c "SELECT 1" > /dev/null 2>&1; then
                  echo "PostgreSQL OK"
                  exit 0
                else
                  echo "PostgreSQL CRITICAL: connection failed"
                  exit 2
                fi
              '';
            }
          );
          inherit check_interval;
        };
        forgejo = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-forgejo";
              runtimeInputs = [ pkgs.curl ];
              text = ''
                if curl -f -s http://${config.machineAddresses.forgejo.guest}:8080 > /dev/null 2>&1; then
                  echo "Forgejo OK"
                  exit 0
                else
                  echo "Forgejo CRITICAL: container not responding"
                  exit 2
                fi
              '';
            }
          );
          inherit check_interval;
        };
        atticd = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-atticd";
              runtimeInputs = [ pkgs.curl ];
              text = ''
                if curl -f -s -H "Host: seminar.border-saurolophus.ts.net" \
                  http://${config.machineAddresses.atticd.guest}:8080 > /dev/null 2>&1; then
                  echo "Atticd OK"
                  exit 0
                else
                  echo "Atticd CRITICAL: container not responding"
                  exit 2
                fi
              '';
            }
          );
          inherit check_interval;
        };
        mcp-nixos = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-mcp-nixos";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.mcp-proxy
              ];
              text = ''
                # mcp-proxyを使ってMCPサーバとして正しく動作しているかチェック
                # プロトコルネゴシエーションが成功すればOK
                if timeout 3 mcp-proxy \
                    http://${config.machineAddresses.mcp-nixos.guest}:8080/mcp \
                    --transport streamablehttp 2>&1 | \
                    grep -q "Negotiated protocol version"; then
                  echo "mcp-nixos OK"
                  exit 0
                else
                  echo "mcp-nixos CRITICAL: MCP server not responding"
                  exit 2
                fi
              '';
            }
          );
          inherit check_interval;
        };
        github-runner-x64 = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-github-runner-x64";
              runtimeInputs = [ pkgs.iputils ];
              text = ''
                if ping -c 1 -W 2 ${config.machineAddresses.github-runner-x64.guest} > /dev/null 2>&1; then
                  echo "GitHub Runner x64 OK"
                  exit 0
                else
                  echo "GitHub Runner x64 CRITICAL: ping failed"
                  exit 2
                fi
              '';
            }
          );
          inherit check_interval;
        };
        github-runner-arm64 = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-github-runner-arm64";
              runtimeInputs = [ pkgs.iputils ];
              text = ''
                if ping -c 1 -W 2 ${config.machineAddresses.github-runner-arm64.guest} > /dev/null 2>&1; then
                  echo "GitHub Runner arm64 OK"
                  exit 0
                else
                  echo "GitHub Runner arm64 CRITICAL: ping failed"
                  exit 2
                fi
              '';
            }
          );
          inherit check_interval;
        };
      };
    };
  };
  # Mackerel APIキー(純粋なキー文字列)をsopsで管理
  sops.secrets."mackerel-api-key" = {
    sopsFile = ../../../secrets/seminar/mackerel.yaml;
    key = "api_key";
    owner = "root";
    group = "root";
    mode = "0400";
  };
  # sops.templatesでTOML形式の設定ファイルを生成
  sops.templates."mackerel-api-key.conf" = {
    content = ''
      apikey = "${config.sops.placeholder."mackerel-api-key"}"
    '';
    mode = "0400";
  };
}
