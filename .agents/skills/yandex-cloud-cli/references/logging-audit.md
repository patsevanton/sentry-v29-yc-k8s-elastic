# Logging, Audit Trails, Backup (yc logging, yc audit-trails, yc backup)

## Cloud Logging (yc logging / yc log)

### Log Groups

```
yc logging group list
yc logging group get <NAME|ID>
yc logging group create --name NAME [--retention-period DUR] [--description DESC]
yc logging group update <NAME|ID> [flags]
yc logging group delete <NAME|ID>
yc logging group stats --name NAME
yc logging group list-resources --name NAME
```

### Reading Logs

```bash
# Read from default log group
yc logging read --folder-id <FOLDER-ID> --since 1h --limit 100

# Read from named group
yc logging read --group-name my-group --since 30m

# Filter by level
yc logging read --group-name my-group --levels error,warn --since 1h

# Filter by resource
yc logging read --group-name my-group \
  --resource-types serverless.function \
  --resource-ids <FUNCTION-ID> \
  --since 2h

# Stream filter
yc logging read --group-name my-group --stream-names my-stream

# Follow (tail -f)
yc logging read --group-name my-group --follow

# Time range
yc logging read --group-name my-group \
  --since "2024-01-15T10:00:00Z" \
  --until "2024-01-15T12:00:00Z"

# Custom filter
yc logging read --group-name my-group --filter 'json_payload.request_id = "abc-123"'
```

### Writing Logs

```bash
yc logging write --group-name my-group \
  --message "Deployment completed" \
  --level info \
  --resource-type custom.app \
  --resource-id my-app-1 \
  --json-payload '{"version": "1.2.3", "status": "ok"}'

# From file
yc logging write --group-name my-group \
  --message "Batch event" \
  --json-file events.json
```

### Log Sinks

```
yc logging sink list
yc logging sink get <NAME|ID>
yc logging sink create --name NAME [flags]
yc logging sink delete <NAME|ID>
```

---

## Audit Trails (yc audit-trails)

### Trail Commands

```
yc audit-trails trail list
yc audit-trails trail get <NAME|ID>
yc audit-trails trail create <NAME> [flags]
yc audit-trails trail update <NAME|ID> [flags]
yc audit-trails trail delete <NAME|ID>
```

### create flags

| Flag | Description |
|------|-------------|
| **Destination** (pick one) | |
| `--destination-bucket NAME` | Send to S3 bucket |
| `--destination-bucket-object-prefix PFX` | Object prefix in bucket |
| `--destination-log-group-id ID` | Send to Cloud Logging group |
| `--destination-yds-database-id ID` | Send to YDS (YDB stream) |
| `--destination-yds-stream NAME` | YDS stream name |
| `--destination-yds-codec RAW\|GZIP\|ZSTD` | Compression codec |
| **Scope** (pick one) | |
| `--filter-all-folder-id ID` | All events from folder |
| `--filter-all-cloud-id ID` | All events from cloud |
| `--filter-all-organisation-id ID` | All events from org |
| `--filter-some-folder-ids ID,...` | Events from specific folders |
| `--filter-some-cloud-ids ID,...` | Events from specific clouds |
| **Other** | |
| `--service-account-id ID` | SA for trail |
| `--labels K=V` | Labels |

### Examples

```bash
# Trail to S3 bucket
yc audit-trails trail create my-trail \
  --service-account-id <SA-ID> \
  --destination-bucket audit-logs-bucket \
  --destination-bucket-object-prefix trails/ \
  --filter-all-folder-id <FOLDER-ID>

# Trail to Cloud Logging
yc audit-trails trail create log-trail \
  --service-account-id <SA-ID> \
  --destination-log-group-id <LOG-GROUP-ID> \
  --filter-all-cloud-id <CLOUD-ID>
```

---

## Cloud Backup (yc backup)

### VMs

```
yc backup vm list
yc backup vm get <VM-ID>
yc backup vm list-policies <VM-ID>
yc backup vm list-applicable-policies <VM-ID>
yc backup vm delete <VM-ID>
```

### Backups

```
yc backup backup list --instance-id <VM-ID>
yc backup backup get <BACKUP-ID>
yc backup backup delete <BACKUP-ID>
yc backup backup recover <BACKUP-ID> --destination-instance-id <VM-ID>
```

### Policies

```
yc backup policy list
yc backup policy get <NAME|ID>
yc backup policy create --file policy.yaml
yc backup policy update <NAME|ID> --file policy.yaml
yc backup policy delete <NAME|ID>
yc backup policy apply --id <POLICY-ID> --instance-ids <VM-ID1>,<VM-ID2>
yc backup policy revoke --id <POLICY-ID> --instance-ids <VM-ID>
```

### Backup Agent

```
yc backup agent list --instance-id <VM-ID>
```
