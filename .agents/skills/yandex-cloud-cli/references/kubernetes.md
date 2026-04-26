# Managed Kubernetes (yc managed-kubernetes / yc k8s)

## Cluster Commands

```
yc k8s cluster list
yc k8s cluster get <NAME|ID>
yc k8s cluster create <NAME> [flags]
yc k8s cluster update <NAME|ID> [flags]
yc k8s cluster delete <NAME|ID>
yc k8s cluster start <NAME|ID>
yc k8s cluster stop <NAME|ID>
yc k8s cluster get-credentials --name NAME [--external] [--force]
yc k8s cluster list-nodes --name NAME
yc k8s list-versions
```

### create flags

| Flag | Description |
|------|-------------|
| `--network-name NAME` | VPC network |
| `--zone ZONE` | Master zone (zonal cluster) |
| `--subnet-name NAME` | Master subnet |
| `--public-ip` | Assign public IP to master |
| `--regional` | HA master across 3 zones |
| `--master-location` | Per-zone master config (for regional) |
| `--release-channel` | regular (default), rapid, stable |
| `--version STRING` | K8s version |
| `--service-account-name NAME` | SA for provisioning resources |
| `--node-service-account-name NAME` | SA for nodes (registry, logs) |
| `--cluster-ipv4-range CIDR` | Pod CIDR |
| `--service-ipv4-range CIDR` | Service CIDR |
| `--security-group-ids ID,...` | Security groups |
| `--enable-network-policy` | Enable Calico network policy |
| `--kms-key-name NAME` | KMS key for secrets encryption |
| `--cilium` | Enable Cilium CNI |
| `--auto-upgrade` | Auto-upgrade master (default true) |

### get-credentials

Downloads kubeconfig for kubectl:

```bash
# External access (via public IP)
yc k8s cluster get-credentials --name my-cluster --external

# Internal access (from within VPC)
yc k8s cluster get-credentials --name my-cluster --internal
```

## Node Group Commands

```
yc k8s node-group list
yc k8s node-group get <NAME|ID>
yc k8s node-group create <NAME> [flags]
yc k8s node-group update <NAME|ID> [flags]
yc k8s node-group delete <NAME|ID>
```

### node-group create flags

| Flag | Description |
|------|-------------|
| `--cluster-name NAME` | Parent cluster |
| `--cores N` | CPU cores per node |
| `--memory SIZE` | RAM per node |
| `--core-fraction N` | CPU baseline % |
| `--disk-type TYPE` | network-hdd, network-ssd |
| `--disk-size SIZE` | Boot disk size |
| `--preemptible` | Use preemptible instances |
| `--fixed-size N` | Fixed node count |
| `--auto-scale min=M,max=N,initial=I` | Autoscaling |
| `--location zone=ZONE,subnet-name=NAME` | Node locations (repeatable) |
| `--platform-id` | Hardware platform |
| `--network-interface` | Network spec (like compute) |
| `--public-ip` | Assign public IPs to nodes |
| `--container-runtime` | containerd (default) |
| `--metadata KEY=VAL` | Node metadata |
| `--labels K=V` | Node group labels |
| `--node-labels K=V` | Kubernetes node labels |
| `--node-taints KEY=VAL:EFFECT` | Kubernetes taints |
| `--max-surge N` | Max extra nodes during update |
| `--max-unavailable N` | Max unavailable during update |
| `--auto-upgrade` | Auto-upgrade nodes |

## Full Cluster Setup Example

```bash
# 1. Create service accounts
yc iam service-account create --name k8s-master
yc iam service-account create --name k8s-nodes

MASTER_SA=$(yc iam service-account get --name k8s-master --format json | jq -r .id)
NODE_SA=$(yc iam service-account get --name k8s-nodes --format json | jq -r .id)
FOLDER_ID=$(yc config get folder-id)

# 2. Assign roles
yc resource-manager folder add-access-binding --id $FOLDER_ID \
  --role k8s.clusters.agent --subject serviceAccount:$MASTER_SA
yc resource-manager folder add-access-binding --id $FOLDER_ID \
  --role vpc.publicAdmin --subject serviceAccount:$MASTER_SA
yc resource-manager folder add-access-binding --id $FOLDER_ID \
  --role container-registry.images.puller --subject serviceAccount:$NODE_SA

# 3. Create cluster
yc k8s cluster create my-cluster \
  --network-name my-net \
  --zone ru-central1-d \
  --subnet-name subnet-d \
  --public-ip \
  --service-account-id $MASTER_SA \
  --node-service-account-id $NODE_SA \
  --release-channel regular

# 4. Create node group
yc k8s node-group create my-nodes \
  --cluster-name my-cluster \
  --cores 4 --memory 8GB --disk-size 64GB --disk-type network-ssd \
  --fixed-size 3 \
  --location zone=ru-central1-d,subnet-name=subnet-d \
  --public-ip

# 5. Get kubeconfig
yc k8s cluster get-credentials --name my-cluster --external
kubectl get nodes
```
