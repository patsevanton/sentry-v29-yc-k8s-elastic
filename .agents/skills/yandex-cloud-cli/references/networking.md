# Networking (yc vpc, yc dns, yc application-load-balancer)

## VPC Network

```
yc vpc network list
yc vpc network get <NAME|ID>
yc vpc network create --name NAME [--description DESC] [--labels K=V]
yc vpc network delete <NAME|ID>
yc vpc network list-subnets --name NAME
yc vpc network list-security-groups --name NAME
```

## Subnet

```
yc vpc subnet list
yc vpc subnet get <NAME|ID>
yc vpc subnet create --name NAME --network-name NET --zone ZONE --range CIDR
yc vpc subnet update <NAME|ID> [flags]
yc vpc subnet delete <NAME|ID>
yc vpc subnet list-used-addresses --name NAME
```

### create flags

| Flag | Description |
|------|-------------|
| `--network-id ID` | Network by ID |
| `--network-name NAME` | Network by name |
| `--zone ZONE` | Availability zone |
| `--range CIDR` | IPv4 CIDR (e.g. 10.1.0.0/24) |
| `--route-table-name NAME` | Attach route table |
| `--domain-name` | DHCP domain name |
| `--domain-name-server` | Custom DNS servers |

## Security Group

Alias: `yc vpc sg`

```
yc vpc security-group list
yc vpc security-group get <NAME|ID>
yc vpc security-group create --name NAME --network-name NET --rule SPEC [--rule SPEC...]
yc vpc security-group update <NAME|ID> [flags]
yc vpc security-group delete <NAME|ID>
yc vpc security-group update-rules <NAME|ID> --add-rule SPEC / --delete-rule-id ID
```

### Rule Spec Format

`--rule "direction=ingress|egress,port=N|any,protocol=tcp|udp|icmp|any,v4-cidrs=[CIDR,...]"`

Port range: use `from-port=N,to-port=M` instead of `port=N`.

### Examples

```bash
# Web server security group
yc vpc security-group create my-sg \
  --network-name my-net \
  --rule "direction=ingress,port=22,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=ingress,port=80,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=ingress,port=443,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=egress,port=any,protocol=any,v4-cidrs=[0.0.0.0/0]"
```

## Address

```
yc vpc address list
yc vpc address create --name NAME --external-ipv4 zone=ZONE
yc vpc address delete <NAME|ID>
```

## Route Table

```
yc vpc route-table list
yc vpc route-table create --name NAME --network-name NET --route destination=CIDR,next-hop=IP
yc vpc route-table delete <NAME|ID>
```

## Gateway (NAT Gateway)

```
yc vpc gateway list
yc vpc gateway create --name NAME
yc vpc gateway delete <NAME|ID>
```

Use with route table: `--route destination=0.0.0.0/0,gateway-id=<GW-ID>`

## DNS Zone

```
yc dns zone list
yc dns zone get <NAME|ID>
yc dns zone create --name NAME --zone DOMAIN. --public-visibility|--private-visibility network-ids=ID1,ID2
yc dns zone delete <NAME|ID>
yc dns zone list-records --name NAME
yc dns zone add-records --name NAME --record "NAME TTL TYPE DATA"
yc dns zone delete-records --name NAME --record "NAME TTL TYPE DATA"
```

### DNS Record Examples

```bash
# A record
yc dns zone add-records --name my-zone \
  --record "app.example.com. 600 A 10.0.0.5"

# CNAME record
yc dns zone add-records --name my-zone \
  --record "www.example.com. 600 CNAME app.example.com."
```

## Typical Network Setup

```bash
# 1. Create network
yc vpc network create --name my-net

# 2. Create subnets in each zone
yc vpc subnet create --name subnet-a --network-name my-net --zone ru-central1-a --range 10.1.0.0/24
yc vpc subnet create --name subnet-b --network-name my-net --zone ru-central1-b --range 10.2.0.0/24
yc vpc subnet create --name subnet-d --network-name my-net --zone ru-central1-d --range 10.3.0.0/24

# 3. Create security group
yc vpc security-group create web-sg --network-name my-net \
  --rule "direction=ingress,port=22,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=ingress,port=80,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=ingress,port=443,protocol=tcp,v4-cidrs=[0.0.0.0/0]" \
  --rule "direction=egress,port=any,protocol=any,v4-cidrs=[0.0.0.0/0]"

# 4. NAT gateway for private subnets
yc vpc gateway create --name nat-gw
yc vpc route-table create --name nat-rt --network-name my-net \
  --route destination=0.0.0.0/0,gateway-id=<NAT-GW-ID>
yc vpc subnet update subnet-a --route-table-name nat-rt
```
