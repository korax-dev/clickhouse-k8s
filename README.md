# clickhouse-k8s

This repository contains resources for deploying ClickHouse and optional ClickHouse Keeper on Kubernetes using the official ClickHouse containers.

## Installing the Chart

```bash
helm repo add clickhouse-k8s https://korax-dev.github.io/clickhouse-k8s
helm repo update
helm install clickhouse clickhouse-k8s/clickhouse -f values.yaml
```

## Upgrading the Chart

```bash
helm repo update
helm upgrade clickhouse clickhouse-k8s/clickhouse
```

For more detailed information on configuration options and usage, please refer to the chart's [README](charts/clickhouse/README.md).

## References

- [ClickHouse Docs](https://clickhouse.com/docs/intro)
- [ClickHouse Server Docker Image](https://hub.docker.com/r/clickhouse/clickhouse-server/)
