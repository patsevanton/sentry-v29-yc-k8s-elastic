# Investigation: ISR=1 with `replicationFactor: 3` in External Kafka

## Summary

When using an **external Kafka** (Managed Kafka) with `provisioning.enabled: true`, the Sentry Helm chart creates all topics with `replicationFactor=3`, but the actual `ISR` (In-Sync Replicas) for each partition remains **1**. This means that all replicas of a topic are placed on the same broker, and the topics are not highly available (HA), despite the declared `replicationFactor: 3`.

## Component Version

- **Helm chart:** `sentry/sentry` **v30.1.0**
- **Problematic configuration block:**

```yaml
externalKafka:
  provisioning:
    enabled: true
    replicationFactor: 3
    numPartitions: 1
```

## Actual Behavior

| Parameter | Expected | Actual |
|-----------|----------|--------|
| `replicationFactor` | 3 | 3 (specified in configuration) |
| `numPartitions` | 1 | 1 |
| `ISR` | 3 | **1** |

## Implications

- All Sentry-created topics (`ingest-events`, `ingest-transactions`, `events`, `outcomes`, `snuba-commit-log`, etc.) have `ISR = 1`.
- If the single broker hosting the partition becomes unavailable, the topic stops accepting messages (write operations fail with `NOT_ENOUGH_REPLICAS` or a similar error).
- The Managed Kafka console marks such topics with the status **"Not highly available"**.
- Setting `replicationFactor: 3` does not guarantee HA because the provisioning logic in the chart **does not control replica distribution across brokers**. It merely specifies the desired replication factor when creating the topic.
- With 1 broker per zone and 3 zones, the total number of brokers is 3, but Kafka does not guarantee even replica distribution by default in managed environments with limited topology.

## Root Cause

1. **Provisioning Job in the chart:** when `externalKafka.provisioning.enabled=true`, a Job (`sentry-kafka-provisioning`) is launched that executes a topic creation script.
2. **The script simply calls `kafka-topics.sh --create --replication-factor 3 --partitions 1 ...`**. It **does not check** the current broker topology, Rack Awareness, or manually set `replica.assignment`.
3. **Managed Kafka from Cloud:** if the cluster has 1 broker per zone (3 total), there is no guarantee that 3 replicas will be distributed across 3 different brokers when a topic is created. In some configurations, all replicas may end up on a single broker, especially if:
   - `rack awareness` is absent (brokers are not annotated with zones);
   - the cluster uses an older Kafka version with a distribution bug;
   - during cluster upgrade/creation, brokers are not yet fully synchronized.
