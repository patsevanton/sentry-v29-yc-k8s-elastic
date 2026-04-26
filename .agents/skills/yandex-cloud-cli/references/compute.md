# Compute (yc compute)

## Instance Commands

```
yc compute instance list [--folder-id ID]
yc compute instance get <NAME|ID>
yc compute instance create <NAME> [flags]
yc compute instance update <NAME|ID> [flags]
yc compute instance delete <NAME|ID>
yc compute instance start <NAME|ID>
yc compute instance stop <NAME|ID>
yc compute instance restart <NAME|ID>
yc compute instance attach-disk <NAME|ID> [flags]
yc compute instance detach-disk <NAME|ID> [flags]
yc compute instance add-one-to-one-nat <NAME|ID> --network-interface-index <N>
yc compute instance remove-one-to-one-nat <NAME|ID> --network-interface-index <N>
```

### create flags

| Flag | Description |
|------|-------------|
| `--zone` | Availability zone (e.g. ru-central1-a, ru-central1-b, ru-central1-d) |
| `--cores` | CPU cores count |
| `--memory` | RAM (e.g. 2GB, 4GB, 8GB) |
| `--core-fraction` | Baseline CPU performance % (5, 20, 50, 100) |
| `--platform` | Hardware platform (standard-v3, highfreq-v3, gpu-standard-v3) |
| `--preemptible` | Preemptible (spot) instance |
| `--public-ip` | Auto-assign public IP |
| `--public-address` | Specific public IP |
| `--hostname` | Custom hostname |
| `--ssh-key FILE` | SSH public key file (creates yc-user) |
| `--metadata KEY=VAL` | Instance metadata |
| `--metadata-from-file KEY=PATH` | Metadata from file (e.g. user-data=cloud-init.yaml) |
| `--service-account-id ID` | SA for instance metadata service |
| `--create-boot-disk` | Boot disk spec (see disk properties below) |
| `--create-disk` | Additional disk spec |
| `--attach-disk` | Attach existing disk |
| `--network-interface` | Network interface spec (see network properties below) |
| `--maintenance-policy` | restart or migrate |
| `--gpus` | GPU count |
| `--placement-group-id` | Placement group |
| `--async` | Don't wait for completion |
| `--labels KEY=VAL` | Labels |

### Disk Properties (--create-boot-disk, --create-disk)

Format: `PROP=VAL[,PROP=VAL...]`

| Property | Description |
|----------|-------------|
| name | Disk name |
| type | network-hdd (default), network-ssd, network-ssd-nonreplicated, network-ssd-io-m3 |
| size | Disk size (e.g. 20GB, 100GB) |
| image-family | Image family (e.g. ubuntu-2204-lts, ubuntu-2404-lts, centos-stream-8) |
| image-id | Specific image ID |
| snapshot-id | Create from snapshot |
| auto-delete | Auto-delete with instance (true/false) |
| device-name | Device name in /dev/disk/by-id/ |
| block-size | Block size in bytes (4K, 8K, 16K, 32K, 64K, 128K) |
| image-folder-id | Folder for image resolution (default: standard-images) |

### Network Interface Properties (--network-interface)

Format: `PROP=VAL[,PROP=VAL...]`

| Property | Description |
|----------|-------------|
| subnet-name | Subnet name |
| subnet-id | Subnet ID |
| address | Internal IP (or auto) |
| ipv4-address | Internal IPv4 (or auto) |
| nat-ip-version | ipv4 for public IP via NAT |
| nat-address | Specific public IP for NAT |
| security-group-ids | Security groups: `[id1,id2]` |

## Common Image Families (folder standard-images)

- `ubuntu-2404-lts` - Ubuntu 24.04
- `ubuntu-2204-lts` - Ubuntu 22.04
- `debian-12` - Debian 12
- `centos-stream-8` - CentOS Stream 8
- `almalinux-9` - AlmaLinux 9
- `container-optimized-image` - COI (Docker-ready)
- `nat-instance-ubuntu-2204` - NAT instance

List all: `yc compute image list --folder-id standard-images`

## Examples

Create Ubuntu VM with public IP:
```bash
yc compute instance create my-vm \
  --zone ru-central1-d \
  --cores 2 --memory 4GB --core-fraction 100 \
  --create-boot-disk image-family=ubuntu-2204-lts,image-folder-id=standard-images,size=20GB,type=network-ssd \
  --network-interface subnet-name=my-subnet,nat-ip-version=ipv4 \
  --ssh-key ~/.ssh/id_rsa.pub
```

Create preemptible instance:
```bash
yc compute instance create worker \
  --zone ru-central1-a \
  --cores 4 --memory 8GB --core-fraction 20 \
  --preemptible \
  --create-boot-disk image-family=ubuntu-2204-lts,image-folder-id=standard-images,size=30GB \
  --network-interface subnet-name=my-subnet
```

## Additional Instance Commands

```
yc compute instance create-with-container <NAME> [flags]  # VM running a Docker container (COI)
yc compute instance update-container <NAME|ID> [flags]     # Update container spec
yc compute instance add-metadata <NAME|ID> --metadata KEY=VAL
yc compute instance remove-metadata <NAME|ID> --keys KEY1,KEY2
yc compute instance add-labels <NAME|ID> --labels KEY=VAL
yc compute instance remove-labels <NAME|ID> --labels KEY1,KEY2
yc compute instance attach-filesystem <NAME|ID> --filesystem-name NAME --device-name DEV
yc compute instance detach-filesystem <NAME|ID> --filesystem-name NAME
yc compute instance update-network-interface <NAME|ID> [flags]
yc compute instance attach-network-interface <NAME|ID> [flags]
yc compute instance detach-network-interface <NAME|ID> [flags]
yc compute instance move <NAME|ID> --destination-folder-id ID
yc compute instance relocate <NAME|ID> --destination-zone ZONE [flags]
yc compute instance get-serial-port-output <NAME|ID>
yc compute instance list-operations <NAME|ID>
```

## Disk Commands

```
yc compute disk list
yc compute disk get <NAME|ID>
yc compute disk create --name NAME --size SIZE --type TYPE --zone ZONE [--source-snapshot-id ID] [--source-image-id ID]
yc compute disk update <NAME|ID> [flags]
yc compute disk delete <NAME|ID>
yc compute disk resize <NAME|ID> --size SIZE
yc compute disk move <NAME|ID> --destination-folder-id ID
yc compute disk relocate <NAME|ID> --destination-zone ZONE
```

Disk types: `network-hdd`, `network-ssd`, `network-ssd-nonreplicated`, `network-ssd-io-m3`

## Snapshot Commands

```
yc compute snapshot list
yc compute snapshot get <NAME|ID>
yc compute snapshot create --disk-id ID --name NAME [--description DESC] [--labels K=V]
yc compute snapshot update <NAME|ID> [flags]
yc compute snapshot delete <NAME|ID>
```

## Snapshot Schedule Commands

Automate periodic snapshots:

```
yc compute snapshot-schedule list
yc compute snapshot-schedule get <NAME|ID>
yc compute snapshot-schedule create <NAME> [flags]
yc compute snapshot-schedule update <NAME|ID> [flags]
yc compute snapshot-schedule delete <NAME|ID>
yc compute snapshot-schedule enable <NAME|ID>
yc compute snapshot-schedule disable <NAME|ID>
yc compute snapshot-schedule add-disks <NAME|ID> --disk-id ID [--disk-id ID2]
yc compute snapshot-schedule remove-disks <NAME|ID> --disk-id ID
yc compute snapshot-schedule list-disks <NAME|ID>
yc compute snapshot-schedule list-snapshots <NAME|ID>
```

### create flags

| Flag | Description |
|------|-------------|
| `--expression CRON` | Cron schedule (e.g. `"0 1 * * *"` = daily at 01:00) |
| `--start-at TIMESTAMP` | First run time |
| `--retention-period DUR` | Delete snapshots older than (e.g. 7d, 30d) |
| `--snapshot-count N` | Keep last N snapshots (alternative to retention-period) |
| `--snapshot-description` | Description for each snapshot |
| `--snapshot-labels K=V` | Labels for each snapshot |

```bash
# Daily snapshots, keep 7 days
yc compute snapshot-schedule create daily-backup \
  --expression "0 2 * * *" \
  --retention-period 168h \
  --snapshot-description "Automated daily snapshot"

# Attach disks
yc compute snapshot-schedule add-disks daily-backup --disk-id <DISK-ID>
```

## Image Commands

```
yc compute image list [--folder-id standard-images]
yc compute image get <NAME|ID>
yc compute image get-latest-from-family <FAMILY> [--folder-id standard-images]
yc compute image create <NAME> [flags]
yc compute image update <NAME|ID> [flags]
yc compute image delete <NAME|ID>
```

### create flags

| Flag | Description |
|------|-------------|
| `--source-disk-name NAME` | From disk |
| `--source-disk-id ID` | From disk ID |
| `--source-snapshot-name NAME` | From snapshot |
| `--source-snapshot-id ID` | From snapshot ID |
| `--source-image-name NAME` | From another image |
| `--source-family FAMILY` | From image family |
| `--source-uri URI` | From S3 object (qcow2/vmdk/raw) |
| `--family FAMILY` | Image family for this image |
| `--min-disk-size SIZE` | Min disk size requirement |
| `--os-type linux\|windows` | OS type |
| `--pooled` | Create image pool |

```bash
# Create custom image from disk
yc compute image create my-golden-image \
  --source-disk-name my-configured-vm-disk \
  --family my-app \
  --description "Golden image v1.2"

# Create image from S3
yc compute image create imported-image \
  --source-uri s3://my-bucket/images/disk.qcow2 \
  --os-type linux
```

## Filesystem Commands

Shared NFS-like filesystems attachable to multiple VMs:

```
yc compute filesystem list
yc compute filesystem get <NAME|ID>
yc compute filesystem create --name NAME --size SIZE --type TYPE --zone ZONE
yc compute filesystem update <NAME|ID> [flags]
yc compute filesystem delete <NAME|ID>
yc compute filesystem resize <NAME|ID> --size SIZE
```

Types: `network-hdd`, `network-ssd`, `network-ssd-io-m3`

```bash
# Create and attach
yc compute filesystem create --name shared-fs --size 100GB --type network-ssd --zone ru-central1-d
yc compute instance attach-filesystem my-vm --filesystem-name shared-fs --device-name shared
# Mount inside VM: mount -t virtiofs shared /mnt/shared
```

## Placement Groups

Anti-affinity for VMs spread across different hardware:

```
yc compute placement-group list
yc compute placement-group create --name NAME --spread-strategy
yc compute placement-group create --name NAME --partition-strategy --partitions N
yc compute placement-group delete <NAME|ID>
```

Use `--placement-group-name NAME` when creating instances.

## GPU Clusters

```
yc compute gpu-cluster list
yc compute gpu-cluster create --name NAME --interconnect-type infiniband --zone ZONE
yc compute gpu-cluster delete <NAME|ID>
```

## Instance Group Commands

Instance groups are managed via YAML spec files:

```
yc compute instance-group list
yc compute instance-group get <NAME|ID>
yc compute instance-group create --file spec.yaml
yc compute instance-group update <NAME|ID> --file spec.yaml
yc compute instance-group delete <NAME|ID>
yc compute instance-group stop <NAME|ID>
yc compute instance-group start <NAME|ID>
yc compute instance-group list-instances <NAME|ID>
yc compute instance-group list-operations <NAME|ID>
yc compute instance-group rolling-restart <NAME|ID>
yc compute instance-group rolling-recreate <NAME|ID>
```

## SSH via yc

```bash
# Direct SSH
yc compute ssh --name <INSTANCE> --identity-file ~/.ssh/id_rsa --login <USER>

# Connect to serial console
yc compute connect-to-serial-port --instance-name <INSTANCE> --ssh-key ~/.ssh/id_rsa --user <USER>
```

## Availability Zones

```bash
yc compute zone list  # List all zones with status
```
