# Serverless (yc serverless / yc sls)

## Functions

Alias: `yc serverless fn`

```
yc serverless function list
yc serverless function get <NAME|ID>
yc serverless function create --name NAME
yc serverless function update <NAME|ID> [flags]
yc serverless function delete <NAME|ID>
yc serverless function invoke <NAME|ID> [--data '{"key":"val"}']
yc serverless function logs <NAME|ID> [--since DURATION] [--follow]
yc serverless function allow-unauthenticated-invoke <NAME|ID>
yc serverless function deny-unauthenticated-invoke <NAME|ID>
```

### Function Versions

```
yc serverless function version list --function-name NAME
yc serverless function version create [flags]
```

### version create flags

| Flag | Description |
|------|-------------|
| `--function-name NAME` | Function name |
| `--runtime STRING` | Runtime (see list below) |
| `--entrypoint STRING` | Entry point (e.g. index.handler) |
| `--memory SIZE` | RAM: 128MB-4GB (default 128MB) |
| `--execution-timeout DUR` | Max execution time (default 3s, max 10m) |
| `--source-path PATH` | Local dir or zip file to upload |
| `--source-version-id ID` | Copy from existing version |
| `--environment KEY=VAL` | Environment variables |
| `--service-account-id ID` | SA for function execution |
| `--network-name NAME` | VPC network access |
| `--subnet-name NAME,...` | Subnets for network access |
| `--secret` | Lockbox secret mapping (see below) |
| `--tags TAG,...` | Version tags (use `$latest` for auto) |
| `--concurrency N` | Max concurrent requests per instance |
| `--min-log-level LEVEL` | trace, debug, info, warn, error, fatal |
| `--log-group-id ID` | Custom log group |
| `--tmpfs-size SIZE` | In-memory /tmp storage |

### Runtimes

```bash
yc serverless function runtime list  # Full list
```

Common: `nodejs18`, `nodejs22`, `python312`, `python311`, `python39`, `golang121`, `golang123`, `java21`, `dotnet8`, `bash-2204`, `r43`, `php82`, `kotlin20`

Always run `yc serverless function runtime list` for the current full list.

### Secret Mapping (--secret)

`--secret name=SECRET_NAME,key=KEY,environment-variable=ENV_VAR`

### Deploy Example

```bash
# Create function
yc serverless function create --name my-api

# Deploy version from local directory
yc serverless function version create \
  --function-name my-api \
  --runtime python312 \
  --entrypoint main.handler \
  --memory 256MB \
  --execution-timeout 30s \
  --source-path ./src \
  --environment DB_HOST=rc1a-xxx.mdb.yandexcloud.net \
  --service-account-id <SA-ID>
```

### Scaling Policies

```bash
yc serverless function set-scaling-policy \
  --function-name my-api \
  --tag '$latest' \
  --zone-instances-limit 3 \
  --zone-requests-limit 100
```

## Triggers

```
yc serverless trigger list
yc serverless trigger get <NAME|ID>
yc serverless trigger create <TYPE> [flags]
yc serverless trigger delete <NAME|ID>
```

Types: `timer`, `message-queue`, `object-storage`, `container-registry`, `cloud-logs`, `iot-device-message`, `iot-broker-message`, `logging`, `billing-budget`, `yds`, `mail`

### Timer Trigger Example

```bash
yc serverless trigger create timer \
  --name cron-job \
  --cron-expression "0 * * * ? *" \
  --invoke-function-name my-api \
  --invoke-function-service-account-id <SA-ID>
```

### Object Storage Trigger Example

```bash
yc serverless trigger create object-storage \
  --name on-upload \
  --bucket-id my-bucket \
  --events create-object \
  --prefix uploads/ \
  --invoke-function-name processor \
  --invoke-function-service-account-id <SA-ID>
```

## Serverless Containers

```
yc serverless container list
yc serverless container get <NAME|ID>
yc serverless container create --name NAME
yc serverless container delete <NAME|ID>
yc serverless container allow-unauthenticated-invoke <NAME|ID>
```

### Container Revision

```bash
yc serverless container revision deploy \
  --container-name my-container \
  --image cr.yandex/<REGISTRY-ID>/my-app:latest \
  --memory 512MB \
  --execution-timeout 30s \
  --cores 1 \
  --service-account-id <SA-ID> \
  --environment KEY=VAL
```

## API Gateway

```
yc serverless api-gateway list
yc serverless api-gateway get <NAME|ID>
yc serverless api-gateway create --name NAME --spec FILE
yc serverless api-gateway update <NAME|ID> --spec FILE
yc serverless api-gateway delete <NAME|ID>
```

Spec is an OpenAPI 3.0 YAML with `x-yc-apigateway-integration` extensions.
