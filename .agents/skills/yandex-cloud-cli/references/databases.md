# Managed Databases

## PostgreSQL (yc managed-postgresql / yc postgresql / yc postgres)

### Cluster Commands

```
yc postgres cluster list
yc postgres cluster get <NAME|ID>
yc postgres cluster create <NAME> [flags]
yc postgres cluster update <NAME|ID> [flags]
yc postgres cluster delete <NAME|ID>
yc postgres cluster start <NAME|ID>
yc postgres cluster stop <NAME|ID>
yc postgres cluster backup <NAME|ID>
yc postgres cluster restore [flags]
yc postgres cluster list-operations <NAME|ID>
yc postgres connect --cluster-name NAME --user USER --database DB
```

### create flags

| Flag | Description |
|------|-------------|
| `--network-name NAME` | VPC network |
| `--environment` | production or prestable |
| `--postgresql-version VER` | 16, 15, 14, 13, 12, 14-1c, 13-1c |
| `--resource-preset ID` | Resource preset (s3-c2-m8, etc.) |
| `--disk-size SIZE` | Storage size |
| `--disk-type TYPE` | network-ssd, network-hdd, local-ssd |
| `--host` | Host spec (see below) |
| `--user` | User spec (see below) |
| `--database` | Database spec (see below) |
| `--security-group-ids ID,...` | Security groups |
| `--deletion-protection` | Prevent accidental deletion |
| `--backup-window-start HH:MM:SS` | Backup start time (UTC) |
| `--backup-retain-period-days N` | Backup retention days |
| `--datalens-access` | Allow DataLens |
| `--websql-access` | Allow WebSQL |
| `--serverless-access` | Allow Serverless |
| `--labels K=V` | Labels |

### Host Spec (--host)

`zone-id=ZONE,subnet-id=ID|subnet-name=NAME[,assign-public-ip=true][,priority=N]`

### User Spec (--user)

`name=USER,password=PASS[,permission=DB1,permission=DB2][,conn-limit=N]`

Or use `generate-password=true` instead of `password=PASS`.

### Database Spec (--database)

`name=DB,owner=USER[,lc-collate=LOCALE][,lc-ctype=LOCALE]`

### Other Sub-commands

```
yc postgres database list --cluster-name NAME
yc postgres database create --cluster-name NAME --name DB --owner USER
yc postgres user list --cluster-name NAME
yc postgres user create --cluster-name NAME --name USER --password PASS --permissions DB1,DB2
yc postgres hosts list --cluster-name NAME
yc postgres hosts add --cluster-name NAME --host zone-id=ZONE,subnet-id=ID
yc postgres backup list --cluster-id ID
```

### Create Example

```bash
yc postgres cluster create my-pg \
  --network-name my-net \
  --environment production \
  --postgresql-version 16 \
  --resource-preset s3-c2-m8 \
  --disk-size 50GB --disk-type network-ssd \
  --host zone-id=ru-central1-d,subnet-name=subnet-d \
  --user name=app,password=SecurePass123 \
  --database name=mydb,owner=app \
  --security-group-ids <SG-ID> \
  --deletion-protection
```

### Resource Presets

List: `yc postgres resource-preset list`

Common: `s3-c2-m8` (2 CPU, 8GB), `s3-c4-m16` (4 CPU, 16GB), `s3-c8-m32` (8 CPU, 32GB)

## MySQL (yc managed-mysql)

Same structure as PostgreSQL. Key differences:
- `yc managed-mysql cluster create` with `--mysql-version` (8.0, 5.7)
- Connect: `yc managed-mysql connect --cluster-name NAME --user USER --database DB`

## ClickHouse (yc managed-clickhouse)

Same CRUD pattern. Use `--clickhouse-version` for version.

```
yc managed-clickhouse cluster list
yc managed-clickhouse cluster create <NAME> --clickhouse-version VER --host ... [flags]
yc managed-clickhouse cluster get <NAME|ID>
yc managed-clickhouse cluster update <NAME|ID> [flags]
yc managed-clickhouse cluster delete <NAME|ID>
```

Supports sharded clusters with `--shard-name`, ZooKeeper hosts with `--zookeeper-host`.

## Redis / Valkey (yc managed-redis)

Note: Service has been rebranded to "Managed Service for Valkey" (Redis fork). CLI commands remain `yc managed-redis`. Supports Valkey 7.2, 8.0, 8.1.

```
yc managed-redis cluster list
yc managed-redis cluster create <NAME> --redis-version VER --host ... [flags]
yc managed-redis cluster get <NAME|ID>
yc managed-redis cluster update <NAME|ID> [flags]
yc managed-redis cluster delete <NAME|ID>
```

## MongoDB (yc managed-mongodb)

Same CRUD pattern. Use `--mongodb-version` for version.

```
yc managed-mongodb cluster list
yc managed-mongodb cluster create <NAME> --mongodb-version VER --host ... [flags]
yc managed-mongodb cluster get <NAME|ID>
yc managed-mongodb cluster update <NAME|ID> [flags]
yc managed-mongodb cluster delete <NAME|ID>
```

## YDB

```
yc ydb database list
yc ydb database get <NAME|ID>
yc ydb database create <NAME> --serverless | --dedicated [flags]
yc ydb database update <NAME|ID> [flags]
yc ydb database delete <NAME|ID>
yc ydb database backup <NAME|ID>
```

### Serverless YDB

```bash
yc ydb database create my-ydb --serverless
```

### Dedicated YDB

```bash
yc ydb database create my-ydb --dedicated \
  --network-name my-net \
  --resource-preset medium \
  --storage-size 50GB --storage-type ssd \
  --zone ru-central1-a,ru-central1-b,ru-central1-d \
  --subnet-name subnet-a,subnet-b,subnet-d
```

## Kafka (yc managed-kafka)

```
yc managed-kafka cluster list
yc managed-kafka cluster get <NAME|ID>
yc managed-kafka cluster create <NAME> [flags]
yc managed-kafka cluster update <NAME|ID> [flags]
yc managed-kafka cluster delete <NAME|ID>
yc managed-kafka cluster start <NAME|ID>
yc managed-kafka cluster stop <NAME|ID>
yc managed-kafka topic list --cluster-name NAME
yc managed-kafka topic get <TOPIC> --cluster-name NAME
yc managed-kafka topic create <TOPIC> --cluster-name NAME --partitions N --replication-factor N [--cleanup-policy compact|delete]
yc managed-kafka topic update <TOPIC> --cluster-name NAME [flags]
yc managed-kafka topic delete <TOPIC> --cluster-name NAME
yc managed-kafka user list --cluster-name NAME
yc managed-kafka user get <USER> --cluster-name NAME
yc managed-kafka user create <USER> --cluster-name NAME --password PASS --permission topic=TOPIC,role=ACCESS_ROLE_PRODUCER
yc managed-kafka user update <USER> --cluster-name NAME [flags]
yc managed-kafka user delete <USER> --cluster-name NAME
yc managed-kafka connector list --cluster-name NAME
yc managed-kafka connector get <NAME> --cluster-name NAME
```

## OpenSearch (yc managed-opensearch / yc opensearch)

```
yc opensearch cluster list
yc opensearch cluster get <NAME|ID>
yc opensearch cluster create <NAME> --file spec.yaml
yc opensearch cluster update <NAME|ID> [flags]
yc opensearch cluster delete <NAME|ID>
yc opensearch cluster start <NAME|ID>
yc opensearch cluster stop <NAME|ID>
yc opensearch cluster backup <NAME|ID>
yc opensearch cluster restore [flags]
yc opensearch node-group list --cluster-name NAME
yc opensearch node-group get <NAME> --cluster-name NAME
yc opensearch node-group add --cluster-name NAME [flags]
yc opensearch node-group update --cluster-name NAME --node-group-name NAME [flags]
yc opensearch node-group delete --cluster-name NAME --node-group-name NAME
yc opensearch backup list --cluster-id ID
yc opensearch backup get <ID>
yc opensearch auth-settings get --cluster-name NAME
yc opensearch auth-settings update --cluster-name NAME [flags]
```

## Greenplum (yc managed-greenplum)

```
yc managed-greenplum cluster list
yc managed-greenplum cluster get <NAME|ID>
yc managed-greenplum cluster create <NAME> [flags]
yc managed-greenplum cluster update <NAME|ID> [flags]
yc managed-greenplum cluster delete <NAME|ID>
yc managed-greenplum cluster start <NAME|ID>
yc managed-greenplum cluster stop <NAME|ID>
yc managed-greenplum cluster backup <NAME|ID>
```

## Resource Presets

All managed database services support:
```bash
yc <service> resource-preset list
```

Common presets across services:
- `s3-c2-m8` — 2 vCPU, 8 GB RAM
- `s3-c4-m16` — 4 vCPU, 16 GB RAM
- `s3-c8-m32` — 8 vCPU, 32 GB RAM
- `s3-c16-m64` — 16 vCPU, 64 GB RAM
- `m3-c2-m16` — 2 vCPU, 16 GB RAM (memory-optimized)
