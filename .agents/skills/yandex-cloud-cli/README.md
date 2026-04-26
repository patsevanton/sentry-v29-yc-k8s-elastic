# Yandex Cloud CLI Skill

Agent skill for managing Yandex Cloud infrastructure via the `yc` CLI. Works with Claude Code, Cursor, Copilot, and 30+ other AI agents.

## Installation

```bash
npx skills add elsvv/yandex-cloud-cli-skill
```

Or for Claude Code only:

```bash
npx skills add elsvv/yandex-cloud-cli-skill --agent claude-code
```

## What's Covered

Comprehensive reference for all major `yc` CLI services:

- **Compute** -- VMs, disks, images, snapshots, instance groups, GPU clusters
- **Networking** -- VPC, subnets, security groups, DNS, gateways, route tables
- **Databases** -- PostgreSQL, MySQL, ClickHouse, Redis/Valkey, MongoDB, OpenSearch, Greenplum, Kafka, YDB
- **Kubernetes** -- Clusters, node groups, kubeconfig, autoscaling
- **Serverless** -- Functions, containers, triggers, API gateways
- **Storage** -- S3 buckets, object operations, Lockbox secrets, KMS encryption
- **Certificates** -- Let's Encrypt auto-renewal, imported certs
- **Load Balancers** -- ALB (L7) and NLB (L4) with full setup examples
- **CDN** -- Origins, caching, SSL, compression, cache purge
- **Container Registry** -- Registries, Docker auth, lifecycle policies
- **IAM** -- Service accounts, roles, access bindings, all key types
- **Organization** -- Federations, groups, OS Login, Smart Web Security, SmartCaptcha
- **Data Platform** -- DataProc (Hadoop/Spark), Data Transfer
- **Observability** -- Cloud Logging, Audit Trails, Backup

## Structure

```
SKILL.md              # Main skill file with essentials + service table
references/
  compute.md          # VMs, disks, images, snapshots
  networking.md       # VPC, subnets, security groups, DNS
  databases.md        # All managed databases
  kubernetes.md       # K8s clusters + full setup example
  serverless.md       # Functions, containers, triggers
  storage-secrets-certs.md  # S3, Lockbox, KMS, certificates
  load-balancers.md   # ALB + NLB with examples
  cdn.md              # CDN resources and caching
  container-registry.md
  iam.md              # IAM, service accounts, roles
  organization.md     # Org manager, WAF, SmartCaptcha
  logging-audit.md    # Logging, audit trails, backup
  data-platform.md    # DataProc, Data Transfer
```

## Usage

Once installed, the skill activates automatically when you mention Yandex Cloud, `yc` CLI, or any YC service name. The agent will use the reference files to generate correct `yc` commands.

Example prompts:
- "Create a VM with 4 cores and 8GB RAM in ru-central1-d"
- "Set up a PostgreSQL cluster with 3 hosts"
- "Deploy a serverless function from a zip file"
- "Configure ALB with HTTPS and Let's Encrypt certificate"
- "Create a Kubernetes cluster with autoscaling node group"

## License

MIT
