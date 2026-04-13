# ClickHouse HA policy for Sentry/Snuba

This project uses distributed (HA) external ClickHouse for Snuba/Sentry.
TLS for native protocol is required in this project.

Required settings in `terragrunt/02-platform/terragrunt.hcl`:

- `external_clickhouse_single_node = false`
- `external_clickhouse_tcp_port = 9440`
- Use native TLS (`9440`) for ClickHouse connections.

Also ensure `clusterName` / `distributedClusterName` point to a cluster from
`system.clusters` where replicas are exposed on port `9440`.

Pre-flight SQL check:

```sql
SELECT cluster, host_name, port
FROM system.clusters
WHERE cluster IN ('default')
ORDER BY cluster, shard_num, replica_num;
```

If `system.clusters` returns `9000`, adjust ClickHouse cluster-side configuration
so `system.clusters` exposes `9440` for the selected cluster.

Otherwise Snuba distributed migrations may fail with:
`snuba.clickhouse.errors.ClickhouseError: Unexpected packet ...:9440`.
