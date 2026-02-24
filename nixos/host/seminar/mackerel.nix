{
  pkgs,
  lib,
  config,
  ...
}:
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
          check_interval = 1;
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
          check_interval = 1;
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
          check_interval = 1;
        };
        postgresql = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-postgresql";
              runtimeInputs = [ pkgs.postgresql ];
              text = ''
                if psql -U postgres -c "SELECT 1" > /dev/null 2>&1; then
                  echo "PostgreSQL OK"
                  exit 0
                else
                  echo "PostgreSQL CRITICAL: connection failed"
                  exit 2
                fi
              '';
            }
          );
          check_interval = 1;
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
          check_interval = 1;
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
          check_interval = 1;
        };
        mcp-nixos = {
          command = lib.getExe (
            pkgs.writeShellApplication {
              name = "check-mcp-nixos";
              runtimeInputs = [ pkgs.curl ];
              text = ''
                if curl -f -s http://${config.machineAddresses.mcp-nixos.guest}:8080 > /dev/null 2>&1; then
                  echo "mcp-nixos OK"
                  exit 0
                else
                  echo "mcp-nixos CRITICAL: microVM not responding"
                  exit 2
                fi
              '';
            }
          );
          check_interval = 1;
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
