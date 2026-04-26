# Object Storage, Lockbox, KMS, Certificate Manager

## Object Storage (yc storage)

### Bucket Commands

```
yc storage bucket list
yc storage bucket get <NAME>
yc storage bucket create --name NAME [flags]
yc storage bucket update <NAME> [flags]
yc storage bucket delete <NAME>
```

### create flags

| Flag | Description |
|------|-------------|
| `--name NAME` | Globally unique bucket name |
| `--default-storage-class CLASS` | standard (default), cold, ice |
| `--max-size BYTES` | Max bucket size (0 = unlimited) |
| `--public-read` | Enable public read access |
| `--public-list` | Enable public listing |
| `--public-config-read` | Enable public config read |
| `--acl ACL` | Predefined ACL (conflicts with --grants) |
| `--grants` | Fine-grained ACL (see below) |
| `--tags K=V` | Bucket tags/labels |

### Grants Spec (--grants)

`grantee-id=ID,grant-type=TYPE,permission=PERM`

Grant types: `grant-type-account`, `grant-type-all-authenticated-users`, `grant-type-all-users`
Permissions: `permission-full-control`, `permission-write`, `permission-write-acp`, `permission-read`, `permission-read-acp`

### update flags

```bash
yc storage bucket update my-bucket \
  --default-storage-class cold \
  --max-size 10737418240 \
  --versioning versioning-enabled  # or versioning-disabled, versioning-suspended
```

### S3-compatible Interface

```bash
# Low-level (s3api)
yc storage s3api put-object --bucket NAME --key path/file.txt --body ./local-file.txt
yc storage s3api get-object --bucket NAME --key path/file.txt ./output.txt
yc storage s3api list-objects --bucket NAME [--prefix path/]
yc storage s3api list-objects-v2 --bucket NAME [--prefix path/]
yc storage s3api delete-object --bucket NAME --key path/file.txt
yc storage s3api delete-objects --bucket NAME --delete '{"Objects":[{"Key":"file1.txt"},{"Key":"file2.txt"}]}'
yc storage s3api head-object --bucket NAME --key path/file.txt
yc storage s3api copy-object --bucket NAME --key dest.txt --copy-source BUCKET/source.txt

# Multipart uploads
yc storage s3api create-multipart-upload --bucket NAME --key large-file.zip
yc storage s3api upload-part --bucket NAME --key large-file.zip --upload-id ID --part-number 1 --body part1.bin
yc storage s3api complete-multipart-upload --bucket NAME --key large-file.zip --upload-id ID --multipart-upload '...'
yc storage s3api abort-multipart-upload --bucket NAME --key large-file.zip --upload-id ID

# High-level (s3) — confirmed commands: cp, mv, rm, presign
yc storage s3 cp ./local-file.txt s3://BUCKET/path/file.txt
yc storage s3 cp s3://BUCKET/path/file.txt ./local-file.txt
yc storage s3 cp s3://BUCKET1/file s3://BUCKET2/file    # copy between buckets
yc storage s3 mv ./local-file.txt s3://BUCKET/path/     # move
yc storage s3 rm s3://BUCKET/path/file.txt               # delete
yc storage s3 rm s3://BUCKET/path/ --recursive           # delete recursively
yc storage s3 presign s3://BUCKET/file.txt [--expires-in 3600]  # presigned URL

# For sync/ls, use AWS CLI with static keys (see below) or yc storage s3api list-objects
```

### S3 Auth via Static Keys

```bash
# Create static access key for S3
yc iam access-key create --service-account-name my-sa
# Returns key_id and secret — use as AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY

# Configure for aws cli
export AWS_ACCESS_KEY_ID=<key_id>
export AWS_SECRET_ACCESS_KEY=<secret>
aws --endpoint-url=https://storage.yandexcloud.net s3 ls
```

### Website Hosting

```bash
yc storage bucket update my-site \
  --website-settings '{"index": "index.html", "error": "error.html"}' \
  --public-read

# Access via: http://my-site.website.yandexcloud.net
```

---

## Lockbox (yc lockbox)

### Secret Management

```
yc lockbox secret list
yc lockbox secret get <NAME|ID>
yc lockbox secret create --name NAME --payload SPEC [flags]
yc lockbox secret update <NAME|ID> [flags]
yc lockbox secret delete <NAME|ID>
yc lockbox secret activate <NAME|ID>
yc lockbox secret deactivate <NAME|ID>
yc lockbox secret list-versions <NAME|ID>
yc lockbox secret add-version --name NAME --payload SPEC
yc lockbox secret schedule-version-destruction <NAME|ID> --version-id VER [--pending-period DUR]
yc lockbox secret cancel-version-destruction <NAME|ID> --version-id VER
```

### create flags

| Flag | Description |
|------|-------------|
| `--name NAME` | Secret name |
| `--payload JSON` | JSON/YAML array of key-value entries |
| `--kms-key-id ID` | Encrypt with KMS key |
| `--version-description DESC` | First version description |
| `--deletion-protection` | Prevent accidental deletion |
| `--labels K=V` | Labels |

### Payload Format

```bash
--payload '[{"key":"DB_PASSWORD","text_value":"secret123"},{"key":"API_KEY","text_value":"abc"}]'

# Binary values
--payload '[{"key":"tls_cert","binary_value":"<base64-encoded>"}]'

# Read from stdin
echo '[{"key":"pass","text_value":"s3cret"}]' | yc lockbox secret create --name my-secret --payload -
```

### Reading Secrets

```bash
yc lockbox payload get --name my-secret                     # All entries
yc lockbox payload get --name my-secret --key DB_PASSWORD   # Single entry
yc lockbox payload get --id <SECRET-ID> --version-id <VER>  # Specific version
```

### Examples

```bash
# Create secret with KMS encryption
yc lockbox secret create --name prod-secrets \
  --kms-key-id <KMS-KEY-ID> \
  --deletion-protection \
  --payload '[{"key":"DB_PASSWORD","text_value":"s3cret"},{"key":"API_KEY","text_value":"abc123"}]'

# Rotate: add new version
yc lockbox secret add-version --name prod-secrets \
  --payload '[{"key":"DB_PASSWORD","text_value":"new-s3cret"},{"key":"API_KEY","text_value":"xyz789"}]'

# Use in serverless function
yc serverless function version create \
  --function-name my-fn \
  --runtime python312 --entrypoint main.handler --source-path ./src \
  --secret name=prod-secrets,key=DB_PASSWORD,environment-variable=DB_PASSWORD

# Use value in script
DB_PASS=$(yc lockbox payload get --name prod-secrets --key DB_PASSWORD --format json | jq -r '.entries[0].text_value')
```

---

## KMS (yc kms)

### Symmetric Keys

```
yc kms symmetric-key list
yc kms symmetric-key get <NAME|ID>
yc kms symmetric-key create --name NAME [--default-algorithm aes-128|aes-192|aes-256] [--rotation-period DUR]
yc kms symmetric-key update <NAME|ID> [flags]
yc kms symmetric-key delete <NAME|ID>
yc kms symmetric-key rotate <NAME|ID>
yc kms symmetric-key list-versions <NAME|ID>
yc kms symmetric-key set-primary-version <NAME|ID> --version-id VER
yc kms symmetric-key schedule-version-destruction <NAME|ID> --version-id VER
yc kms symmetric-key cancel-version-destruction <NAME|ID> --version-id VER
```

### Crypto Operations

```bash
# Encrypt file
yc kms symmetric-crypto encrypt --name my-key \
  --plaintext-file input.txt --ciphertext-file output.enc

# Decrypt file
yc kms symmetric-crypto decrypt --name my-key \
  --ciphertext-file output.enc --plaintext-file decrypted.txt

# Generate data encryption key (envelope encryption)
yc kms symmetric-crypto generate-data-key --name my-key \
  --data-key-spec aes-256

# Re-encrypt with different key version
yc kms symmetric-crypto re-encrypt --name my-key \
  --source-ciphertext-file old.enc --ciphertext-file new.enc
```

### Use Cases

- Encrypt K8s secrets: `yc k8s cluster create --kms-key-name my-key`
- Encrypt disks: `--create-boot-disk kms-key-name=my-key`
- Encrypt Lockbox secrets: `yc lockbox secret create --kms-key-id <ID>`

---

## Certificate Manager (yc certificate-manager / yc cm)

### Certificate Commands

```
yc cm certificate list
yc cm certificate get <NAME|ID>
yc cm certificate create --name NAME [flags]      # Import existing cert
yc cm certificate request --name NAME [flags]      # Request Let's Encrypt
yc cm certificate update <NAME|ID> [flags]
yc cm certificate delete <NAME|ID>
yc cm certificate content --name NAME              # Download chain + key
yc cm certificate list-operations <NAME|ID>
```

### Request (Let's Encrypt) Flags

| Flag | Description |
|------|-------------|
| `--name NAME` | Certificate name |
| `--domains D1,D2` | Domain names |
| `--challenge dns\|http` | Validation method |
| `--deletion-protection` | Prevent deletion |

### Import (create) Flags

| Flag | Description |
|------|-------------|
| `--name NAME` | Certificate name |
| `--chain FILE` | PEM certificate chain file |
| `--key FILE` | PEM private key file |
| `--domains D1,D2` | Domains (optional for import) |

### Examples

```bash
# Request Let's Encrypt certificate (DNS validation)
yc cm certificate request --name my-cert \
  --domains example.com,www.example.com \
  --challenge dns

# Check status — will show required DNS records for validation
yc cm certificate get --name my-cert

# After adding DNS records and validation succeeds:
yc cm certificate get --name my-cert  # status: ISSUED

# Import existing certificate
yc cm certificate create --name imported-cert \
  --chain /path/to/fullchain.pem \
  --key /path/to/privkey.pem

# Download certificate content
yc cm certificate content --name my-cert

# Use with ALB
yc alb load-balancer add-listener my-lb \
  --listener-name https \
  --external-ipv4-endpoint port=443 \
  --http-router-name my-router \
  --enable-tls \
  --certificate-id $(yc cm certificate get --name my-cert --format json | jq -r .id)

# Use with CDN
yc cdn resource create cdn.example.com \
  --cert-manager-ssl-cert-id $(yc cm certificate get --name my-cert --format json | jq -r .id) \
  --origin-custom-source origin.example.com
```
