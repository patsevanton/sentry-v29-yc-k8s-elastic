# ClickHouse HA policy for Sentry/Snuba

This project uses distributed (HA) external ClickHouse for Snuba/Sentry.
TLS for native protocol is intentionally disabled in this project.

Required settings in `terragrunt/02-platform/terragrunt.hcl`:

- `external_clickhouse_single_node = false`
- `external_clickhouse_tcp_port = 9000`
- Do NOT use TLS/native `9440`.

Also ensure `clusterName` / `distributedClusterName` point to a cluster from
`system.clusters` where replicas are exposed on port `9000`.

Pre-flight SQL check:

```sql
SELECT cluster, host_name, port
FROM system.clusters
WHERE cluster IN ('default')
ORDER BY cluster, shard_num, replica_num;
```

If `system.clusters` returns `9440`, this project still must remain on plaintext
`9000` (no TLS). In such case, adjust ClickHouse cluster-side configuration so
`system.clusters` exposes `9000` for the selected cluster.

Otherwise Snuba distributed migrations may fail with:
`snuba.clickhouse.errors.ClickhouseError: Unexpected packet ...:9440`.
