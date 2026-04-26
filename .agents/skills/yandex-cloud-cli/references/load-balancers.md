# Load Balancers (yc application-load-balancer, yc load-balancer)

## Application Load Balancer — ALB (L7)

Alias: `yc alb`

### Components

ALB consists of 4 components linked together:
1. **Target Group** — set of IP:port targets (VMs, containers)
2. **Backend Group** — backends with health checks pointing to target groups
3. **HTTP Router** + **Virtual Hosts** — routing rules
4. **Load Balancer** — listener endpoints binding it all together

### Target Group

```
yc alb target-group list
yc alb target-group get <NAME|ID>
yc alb target-group create --name NAME --target subnet-name=SUBNET,ip-address=IP [--target ...]
yc alb target-group update <NAME|ID> [flags]
yc alb target-group delete <NAME|ID>
yc alb target-group add-targets <NAME|ID> --target subnet-name=SUBNET,ip-address=IP
yc alb target-group remove-targets <NAME|ID> --target subnet-name=SUBNET,ip-address=IP
```

### Backend Group

Alias: `yc alb bg`

```
yc alb backend-group list
yc alb backend-group get <NAME|ID>
yc alb backend-group create --name NAME
yc alb backend-group update <NAME|ID> [flags]
yc alb backend-group delete <NAME|ID>
```

#### Add HTTP Backend

```bash
yc alb backend-group add-http-backend <BG-NAME> \
  --name my-backend \
  --port 80 \
  --target-group-name my-tg \
  --weight 1 \
  --http-healthcheck port=80,path=/health,interval=5s,timeout=2s,healthy-threshold=2,unhealthy-threshold=3
```

Healthcheck types: `--http-healthcheck`, `--grpc-healthcheck`, `--stream-healthcheck`

#### Add gRPC / Stream Backend

```bash
yc alb backend-group add-grpc-backend <BG-NAME> --name grpc-be --port 9090 --target-group-name my-tg
yc alb backend-group add-stream-backend <BG-NAME> --name stream-be --port 8080 --target-group-name my-tg
```

Update/delete backends:
```
yc alb backend-group update-http-backend <BG-NAME> --name BACKEND [flags]
yc alb backend-group delete-http-backend <BG-NAME> --name BACKEND
```

### HTTP Router

Alias: `yc alb router`

```
yc alb http-router list
yc alb http-router create --name NAME
yc alb http-router delete <NAME|ID>
```

### Virtual Host

Alias: `yc alb vh`

```
yc alb virtual-host list --http-router-name ROUTER
yc alb virtual-host create <VH-NAME> --http-router-name ROUTER --authority "example.com,*.example.com"
yc alb virtual-host update <VH-NAME> --http-router-name ROUTER [flags]
yc alb virtual-host delete <VH-NAME> --http-router-name ROUTER
```

#### Routes

```bash
# Append HTTP route
yc alb virtual-host append-http-route \
  --virtual-host-name my-vh \
  --http-router-name my-router \
  --match-http-method GET,POST \
  --exact-path-match /api/v1 \
  --backend-group-name my-bg \
  --route-name api-route

# With prefix match
yc alb virtual-host append-http-route \
  --virtual-host-name my-vh \
  --http-router-name my-router \
  --prefix-path-match /static \
  --backend-group-name static-bg \
  --route-name static-route

# Redirect route
yc alb virtual-host append-http-route \
  --virtual-host-name my-vh \
  --http-router-name my-router \
  --prefix-path-match / \
  --redirect-to https://example.com \
  --route-name redirect-route
```

Other route operations: `prepend-http-route`, `insert-http-route`, `update-http-route`, `remove-http-route`

gRPC routes: `append-grpc-route`, `prepend-grpc-route`, `update-grpc-route`, `remove-grpc-route`

### Load Balancer

Alias: `yc alb lb`

```
yc alb load-balancer list
yc alb load-balancer get <NAME|ID>
yc alb load-balancer create <NAME> --network-name NET --location zone=ZONE,subnet-name=SUBNET [flags]
yc alb load-balancer update <NAME|ID> [flags]
yc alb load-balancer delete <NAME|ID>
yc alb load-balancer start <NAME|ID>
yc alb load-balancer stop <NAME|ID>
yc alb load-balancer target-states <NAME|ID> --target-group-name TG --backend-group-name BG
```

#### create flags

| Flag | Description |
|------|-------------|
| `--network-name NAME` | VPC network |
| `--location` | Zone+subnet pairs (repeatable) |
| `--security-group-ids ID,...` | Security groups (comma-separated) |
| `--log-group-id ID` | Log group for access logs |
| `--disable-logging` | No access logs |

#### Add Listener

```bash
# HTTP listener
yc alb load-balancer add-listener <LB-NAME> \
  --listener-name http-listener \
  --external-ipv4-endpoint port=80 \
  --http-router-name my-router

# HTTPS listener with TLS
yc alb load-balancer add-listener <LB-NAME> \
  --listener-name https-listener \
  --external-ipv4-endpoint port=443 \
  --http-router-name my-router \
  --enable-tls \
  --certificate-id <CERT-ID>

# HTTP→HTTPS redirect
yc alb load-balancer add-listener <LB-NAME> \
  --listener-name redirect-listener \
  --external-ipv4-endpoint port=80 \
  --redirect-to-https

# Stream (TCP) listener
yc alb load-balancer add-stream-listener <LB-NAME> \
  --listener-name tcp-listener \
  --external-ipv4-endpoint port=5432 \
  --backend-group-name pg-bg
```

### Full ALB Setup Example

```bash
# 1. Target group with VM IPs
yc alb target-group create --name web-tg \
  --target subnet-name=subnet-d,ip-address=10.3.0.10 \
  --target subnet-name=subnet-d,ip-address=10.3.0.11

# 2. Backend group with health check
yc alb backend-group create --name web-bg
yc alb backend-group add-http-backend web-bg \
  --name web-be --port 80 --target-group-name web-tg \
  --http-healthcheck port=80,path=/health,interval=5s,timeout=2s,healthy-threshold=2,unhealthy-threshold=3

# 3. HTTP router + virtual host + route
yc alb http-router create --name web-router
yc alb virtual-host create default-vh \
  --http-router-name web-router \
  --authority "*"
yc alb virtual-host append-http-route \
  --virtual-host-name default-vh \
  --http-router-name web-router \
  --prefix-path-match / \
  --backend-group-name web-bg \
  --route-name default-route

# 4. Load balancer with HTTPS
yc alb load-balancer create web-lb \
  --network-name my-net \
  --location zone=ru-central1-d,subnet-name=subnet-d
yc alb load-balancer add-listener web-lb \
  --listener-name https --external-ipv4-endpoint port=443 \
  --http-router-name web-router --enable-tls --certificate-id <CERT-ID>
yc alb load-balancer add-listener web-lb \
  --listener-name http-redirect --external-ipv4-endpoint port=80 \
  --redirect-to-https
```

---

## Network Load Balancer — NLB (L4)

Alias: `yc lb`

### Target Group

```
yc lb target-group list
yc lb target-group get <NAME|ID>
yc lb target-group create --name NAME --target subnet-name=SUBNET,address=IP [--target ...]
yc lb target-group update <NAME|ID> [flags]
yc lb target-group delete <NAME|ID>
yc lb target-group add-targets <NAME|ID> --target subnet-name=SUBNET,address=IP
yc lb target-group remove-targets <NAME|ID> --target subnet-name=SUBNET,address=IP
```

### Network Load Balancer

Alias: `yc lb nlb`

```
yc lb nlb list
yc lb nlb get <NAME|ID>
yc lb nlb create <NAME> [flags]
yc lb nlb update <NAME|ID> [flags]
yc lb nlb delete <NAME|ID>
yc lb nlb start <NAME|ID>
yc lb nlb stop <NAME|ID>
yc lb nlb attach-target-group <NAME|ID> [flags]
yc lb nlb detach-target-group <NAME|ID> --target-group-id ID
yc lb nlb add-listener <NAME|ID> [flags]
yc lb nlb remove-listener <NAME|ID> --listener NAME
yc lb nlb target-states <NAME|ID> --target-group-id ID
```

#### create flags

| Flag | Description |
|------|-------------|
| `--type` | external (default) or internal |
| `--listener` | Listener spec (see below) |
| `--target-group` | Target group + healthcheck spec |
| `--deletion-protection` | Prevent deletion |
| `--labels K=V` | Labels |

#### Listener Spec (--listener)

`name=NAME,port=PORT[,target-port=PORT][,protocol=tcp|udp][,external-ip-version=ipv4][,internal-subnet-id=ID]`

#### Target Group Spec (--target-group)

`target-group-id=ID,healthcheck-name=NAME,healthcheck-tcp-port=PORT[,healthcheck-interval=2s][,healthcheck-timeout=1s]`

Or with HTTP healthcheck: `healthcheck-http-port=PORT,healthcheck-http-path=/health`

### NLB Example

```bash
# 1. Target group
yc lb target-group create --name app-tg \
  --target subnet-name=subnet-d,address=10.3.0.10 \
  --target subnet-name=subnet-d,address=10.3.0.11

# 2. External NLB
yc lb nlb create app-nlb \
  --type external \
  --listener name=http,port=80,target-port=8080,protocol=tcp \
  --target-group target-group-id=$(yc lb target-group get --name app-tg --format json | jq -r .id),healthcheck-name=http,healthcheck-http-port=8080,healthcheck-http-path=/health

# 3. Internal NLB
yc lb nlb create internal-lb \
  --type internal \
  --listener name=pg,port=5432,protocol=tcp,internal-subnet-id=<SUBNET-ID> \
  --target-group target-group-id=<TG-ID>,healthcheck-name=tcp,healthcheck-tcp-port=5432
```
