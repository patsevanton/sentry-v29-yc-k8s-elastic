# IAM & Resource Manager (yc iam, yc resource-manager)

## Current Identity

```bash
yc config list                      # Show current profile, cloud, folder, token
yc iam create-token                 # Get IAM token for current auth
```

## Clouds & Folders

```
yc resource-manager cloud list
yc resource-manager cloud get <NAME|ID>
yc resource-manager folder list [--cloud-id ID]
yc resource-manager folder get <NAME|ID>
yc resource-manager folder create --name NAME [--cloud-id ID]
yc resource-manager folder update <NAME|ID> [--new-name NAME]
yc resource-manager folder delete <NAME|ID>
```

### Folder Access Bindings

```bash
yc resource-manager folder list-access-bindings --id <FOLDER-ID>
yc resource-manager folder add-access-binding --id <FOLDER-ID> \
  --role <ROLE> \
  --subject serviceAccount:<SA-ID>
yc resource-manager folder remove-access-binding --id <FOLDER-ID> \
  --role <ROLE> \
  --subject serviceAccount:<SA-ID>
```

## Service Accounts

```
yc iam service-account list
yc iam service-account get <NAME|ID>
yc iam service-account create --name NAME [--description DESC]
yc iam service-account update <NAME|ID> [flags]
yc iam service-account delete <NAME|ID>
```

## Keys & Credentials

### IAM Keys (for API auth)
```bash
yc iam key create --service-account-name NAME -o key.json
yc iam key list --service-account-name NAME
yc iam key delete <KEY-ID>
```

### Static Access Keys (for S3/AWS-compatible APIs)
```bash
yc iam access-key create --service-account-name NAME
yc iam access-key list --service-account-name NAME
yc iam access-key delete <KEY-ID>
```

### API Keys (for some services like AI/ML)
```bash
yc iam api-key create --service-account-name NAME
yc iam api-key list --service-account-name NAME
yc iam api-key delete <KEY-ID>
```

## Roles

```bash
yc iam role list                    # All available roles
yc iam role get <ROLE-ID>           # Role details
```

### Common Roles

| Role | Description |
|------|-------------|
| `admin` | Full access |
| `editor` | Edit everything (no IAM) |
| `viewer` | Read-only |
| `compute.admin` | Manage compute resources |
| `vpc.admin` | Manage VPC resources |
| `storage.admin` | Manage object storage |
| `storage.editor` | Upload/delete objects |
| `container-registry.images.pusher` | Push to container registry |
| `k8s.admin` | Manage Kubernetes |
| `serverless.functions.invoker` | Invoke serverless functions |
| `lockbox.payloadViewer` | Read lockbox secrets |
| `iam.serviceAccounts.tokenCreator` | Create tokens for SA |
| `resource-manager.clouds.member` | Cloud membership |

### Assign Roles

```bash
# Assign role to SA at folder level
yc resource-manager folder add-access-binding --id <FOLDER-ID> \
  --role editor \
  --subject serviceAccount:<SA-ID>

# Assign role at cloud level
yc resource-manager cloud add-access-binding --id <CLOUD-ID> \
  --role viewer \
  --subject userAccount:<USER-ID>
```

## Typical SA Setup

```bash
# 1. Create service account
yc iam service-account create --name deployer --description "CI/CD deployer"

# 2. Assign roles
SA_ID=$(yc iam service-account get --name deployer --format json | jq -r .id)
FOLDER_ID=$(yc config get folder-id)

yc resource-manager folder add-access-binding --id $FOLDER_ID \
  --role editor --subject serviceAccount:$SA_ID
yc resource-manager folder add-access-binding --id $FOLDER_ID \
  --role container-registry.images.pusher --subject serviceAccount:$SA_ID

# 3. Create auth key
yc iam key create --service-account-name deployer -o deployer-key.json

# 4. Use key in profile
yc config profile create deployer
yc config set service-account-key deployer-key.json
yc config set folder-id $FOLDER_ID
```
