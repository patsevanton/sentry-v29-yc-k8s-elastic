# Data Platform (yc dataproc, yc datatransfer)

## DataProc (yc dataproc)

### Cluster Commands

```
yc dataproc cluster list
yc dataproc cluster get <NAME|ID>
yc dataproc cluster create <NAME> [flags]
yc dataproc cluster update <NAME|ID> [flags]
yc dataproc cluster delete <NAME|ID>
yc dataproc cluster start <NAME|ID>
yc dataproc cluster stop <NAME|ID>
```

### create flags

| Flag | Description |
|------|-------------|
| `--zone ZONE` | Availability zone |
| `--service-account-name NAME` | SA for cluster |
| `--version VER` | Image version |
| `--services SVC,...` | hdfs, yarn, mapreduce, hive, tez, zookeeper, hbase, sqoop, flume, spark, zeppelin |
| `--bucket NAME` | S3 bucket for jobs |
| `--ssh-public-keys-file FILE` | SSH public keys |
| `--subcluster` | Subcluster spec (repeatable, see below) |
| `--property SVC:KEY=VAL` | Hadoop properties (e.g. `hdfs:dfs.replication=3`) |
| `--initialization-action` | Init scripts (uri=URI,args=ARGS,timeout=SEC) |
| `--security-group-ids ID,...` | Security groups |
| `--ui-proxy` | Enable UI proxy (Zeppelin, YARN UI) |
| `--labels K=V` | Labels |
| `--deletion-protection` | Prevent deletion |
| `--log-group-id ID` | Custom log group |

### Subcluster Spec (--subcluster)

`name=NAME,role=masternode|datanode|computenode,resource-preset=ID,disk-type=TYPE,disk-size=SIZE,hosts-count=N,subnet-name=SUBNET[,assign-public-ip=true]`

For autoscaling compute nodes add: `max-hosts-count=N,cpu-utilization-target=PCT,warmup-duration=DUR,stabilization-duration=DUR`

### Subcluster Commands

```
yc dataproc subcluster list --cluster-name NAME
yc dataproc subcluster get <NAME|ID> --cluster-name NAME
yc dataproc subcluster create <NAME> --cluster-name NAME [flags]
yc dataproc subcluster update <NAME|ID> --cluster-name NAME [flags]
yc dataproc subcluster delete <NAME|ID> --cluster-name NAME
```

### Job Commands

```
yc dataproc job list --cluster-name NAME
yc dataproc job get <ID> --cluster-name NAME
yc dataproc job create-spark --cluster-name NAME --main-jar-file-uri URI [flags]
yc dataproc job create-pyspark --cluster-name NAME --main-python-file-uri URI [flags]
yc dataproc job create-mapreduce --cluster-name NAME [flags]
yc dataproc job create-hive --cluster-name NAME [flags]
yc dataproc job cancel <ID> --cluster-name NAME
yc dataproc job log <ID> --cluster-name NAME
```

### Example: Spark Cluster

```bash
yc dataproc cluster create spark-cluster \
  --zone ru-central1-d \
  --service-account-name dataproc-sa \
  --version 2.1 \
  --services hdfs,yarn,spark,livy \
  --bucket dataproc-jobs \
  --ssh-public-keys-file ~/.ssh/id_rsa.pub \
  --subcluster name=master,role=masternode,resource-preset=s3-c4-m16,disk-type=network-ssd,disk-size=100GB,hosts-count=1,subnet-name=subnet-d,assign-public-ip=true \
  --subcluster name=data,role=datanode,resource-preset=s3-c8-m32,disk-type=network-ssd,disk-size=200GB,hosts-count=3,subnet-name=subnet-d \
  --security-group-ids <SG-ID> \
  --ui-proxy
```

Submit a Spark job:
```bash
yc dataproc job create-spark \
  --cluster-name spark-cluster \
  --name my-job \
  --main-jar-file-uri s3a://dataproc-jobs/my-app.jar \
  --main-class com.example.MyApp \
  --args arg1,arg2 \
  --properties spark.executor.memory=4g,spark.executor.cores=2
```

---

## Data Transfer (yc datatransfer / yc dt)

### Endpoints

```
yc dt endpoint list
yc dt endpoint get <ID>
yc dt endpoint delete <ID>
```

Endpoints are created by type:
```
yc dt endpoint create postgres-source [flags]
yc dt endpoint create postgres-target [flags]
yc dt endpoint create mysql-source [flags]
yc dt endpoint create mysql-target [flags]
yc dt endpoint create mongo-source [flags]
yc dt endpoint create mongo-target [flags]
yc dt endpoint create clickhouse-source [flags]
yc dt endpoint create clickhouse-target [flags]
yc dt endpoint create yds-source [flags]
yc dt endpoint create yds-target [flags]
```

### Transfers

```
yc dt transfer list
yc dt transfer get <ID>
yc dt transfer create --name NAME --source-id SRC --target-id TGT --type TYPE [flags]
yc dt transfer update <ID> [flags]
yc dt transfer delete <ID>
yc dt transfer activate <ID>
yc dt transfer deactivate <ID>
```

Transfer types: `snapshot-only`, `increment-only`, `snapshot-and-increment`

### Example

```bash
# Create PostgreSQL source endpoint
yc dt endpoint create postgres-source \
  --name pg-source \
  --cluster-id <PG-CLUSTER-ID> \
  --user transfer-user \
  --password <PASSWORD> \
  --database mydb

# Create ClickHouse target endpoint
yc dt endpoint create clickhouse-target \
  --name ch-target \
  --cluster-id <CH-CLUSTER-ID> \
  --user transfer-user \
  --password <PASSWORD> \
  --database analytics

# Create and activate transfer
yc dt transfer create \
  --name pg-to-ch \
  --source-id <SRC-EP-ID> \
  --target-id <TGT-EP-ID> \
  --type snapshot-and-increment
yc dt transfer activate <TRANSFER-ID>
```
