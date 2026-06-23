{ config, ... }:
let
  garageAddr = config.machineAddresses.garage.guest;
in
{
  # PrometheusメトリクスをOpenTelemetry Collectorでスクレイプし、
  # OTLPでMackerelに転送します。
  #
  # 専用のPrometheus + Grafanaスタックは立てず、
  # 既にホストで動いているMackerelに一本化します。
  # `mackerel-plugin-prometheus-exporter`ではなくOTel Collectorを使うのは、
  # プラグイン方式だとヒストグラムのバケットが平坦化されてレイテンシの
  # パーセンタイルが失われるためです。
  services.opentelemetry-collector = {
    enable = true;
    settings = {
      receivers.prometheus.config.scrape_configs = [
        {
          job_name = "garage";
          # Mackerelのメトリクス粒度は1分なので、それに合わせて1分間隔にします。
          scrape_interval = "60s";
          scheme = "http";
          metrics_path = "/metrics";
          # `GARAGE_METRICS_TOKEN`はGarageコンテナと同じsopsシークレットを、
          # `EnvironmentFile`経由で渡し、
          # collectorの環境変数展開で参照します。
          authorization = {
            type = "Bearer";
            credentials = "\${env:GARAGE_METRICS_TOKEN}";
          };
          static_configs = [ { targets = [ "${garageAddr}:3903" ]; } ];
        }
      ];
      processors = {
        # 公式ベストプラクティスに従いmemory_limiterをパイプライン先頭に置き、
        # collectorのメモリ上限を確定させてホスト全体のOOMを防ぎます。
        # 通常時のメモリは小さいので、転送失敗時の上限を抑えるのが主目的です。
        memory_limiter = {
          check_interval = "1s";
          limit_mib = 256;
          spike_limit_mib = 64;
        };
        # Mackerelのラベル付きメトリクスは課金対象なので、
        # ボトルネック調査に有用なメトリクスファミリーのみ残します。
        # filterのconditionはtrueになったメトリクスを破棄するので、
        # 対象プレフィックスにマッチしないものを破棄します。
        # プレフィックス一致なので、
        # prometheus receiverによる名前正規化(_total付与等)が起きても取りこぼしません。
        "filter/garage" = {
          error_mode = "ignore";
          metrics.metric = [
            ''not IsMatch(name, "^(api_s3_|block_|rpc_|table_|cluster_)")''
          ];
        };
        batch = { };
      };
      # `otlp` exporterはv0.144.0で`otlp_grpc`にリネームされ、
      # `otlp`はdeprecatedエイリアスになったため`otlp_grpc`を使います。
      exporters."otlp_grpc/mackerel" = {
        # TLSはデフォルトで有効(Mackerelが要求)なので明示設定は不要です。
        endpoint = "otlp.mackerelio.com:4317";
        headers."Mackerel-Api-Key" = "\${env:MACKEREL_APIKEY}";
      };
      service.pipelines.metrics = {
        receivers = [ "prometheus" ];
        processors = [
          "memory_limiter"
          "filter/garage"
          "batch"
        ];
        exporters = [ "otlp_grpc/mackerel" ];
      };
    };
  };

  systemd.services.opentelemetry-collector = {
    serviceConfig = {
      # collector内部のmemory_limiterに加えて、
      # cgroupレベルでもメモリ上限を設けて二重に保護します。
      # memory_limiterのlimit_mib(256MiB)より上に設定して、
      # 通常はcollector側で先に制御が効くようにします。
      MemoryHigh = "384M";
      MemoryMax = "512M";
      # `EnvironmentFile`はsystemdがroot権限で読み込んでからプロセスに渡すため、
      # `DynamicUser`で動くcollectorでも`0400 root`のままアクセスできます。
      EnvironmentFile = [ config.sops.templates."otelcol-env".path ];
    };
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
  };

  # `GARAGE_METRICS_TOKEN`: Garageの`/metrics`アクセス用Bearerトークン(garage.nixで定義)。
  # `MACKEREL_APIKEY`: MackerelのAPIキー(mackerel.nixで定義)。
  # どちらも既存のsopsシークレットのプレースホルダを参照するだけで、
  # 新規シークレットの作成は不要です。
  sops.templates."otelcol-env".content = ''
    GARAGE_METRICS_TOKEN=${config.sops.placeholder."garage-metrics-token"}
    MACKEREL_APIKEY=${config.sops.placeholder."mackerel-api-key"}
  '';
}
