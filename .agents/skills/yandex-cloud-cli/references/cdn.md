# CDN (yc cdn)

## Provider

Before using CDN, activate the provider:

```bash
yc cdn provider activate --type gcore
yc cdn resource get-provider-cname  # Get CNAME for DNS setup
```

## Origin Group

```
yc cdn origin-group list
yc cdn origin-group get <NAME|ID>
yc cdn origin-group create --name NAME --origin source=ORIGIN [--origin source=BACKUP,backup=true]
yc cdn origin-group update <ID> [flags]
yc cdn origin-group delete <ID>
```

### Origin Spec (--origin)

`source=HOSTNAME_OR_IP[,enabled=true][,backup=true][,meta-bucket-name=NAME][,meta-website-name=NAME][,meta-balancer-id=ID]`

### Examples

```bash
# Origins from custom servers
yc cdn origin-group create --name my-origins \
  --origin source=origin1.example.com,enabled=true \
  --origin source=origin2.example.com,backup=true \
  --use-next

# Origin from S3 bucket
yc cdn origin-group create --name bucket-origin \
  --origin source=my-bucket.storage.yandexcloud.net,meta-bucket-name=my-bucket

# Origin from ALB
yc cdn origin-group create --name alb-origin \
  --origin source=<ALB-IP-or-DOMAIN>,meta-balancer-id=<ALB-ID>
```

## CDN Resource

```
yc cdn resource list
yc cdn resource get <ID>
yc cdn resource create <CNAME> [flags]
yc cdn resource update <ID> [flags]
yc cdn resource delete <ID>
yc cdn resource get-provider-cname
```

### create flags

| Flag | Description |
|------|-------------|
| **Origin** | |
| `--origin-group-id ID` | Use origin group |
| `--origin-custom-source HOST` | Single custom origin |
| `--origin-bucket-source HOST` | S3 bucket origin |
| `--origin-bucket-name NAME` | Bucket name (with bucket-source) |
| `--origin-balancer-source HOST` | ALB origin |
| `--origin-balancer-id ID` | Balancer ID (with balancer-source) |
| `--origin-protocol` | http, https, or match |
| **Hostnames** | |
| `--secondary-hostnames` | Additional CNAMEs |
| **SSL/TLS** | |
| `--dont-use-ssl-cert` | No HTTPS |
| `--lets-encrypt-gcore-ssl-cert` | Auto Let's Encrypt cert |
| `--cert-manager-ssl-cert-id ID` | YC Certificate Manager cert |
| **Caching** | |
| `--disable-cache` | No CDN caching |
| `--cache-expiration-time SEC` | Cache TTL for 2xx/3xx |
| `--cache-expiration-time-default SEC` | Cache by origin headers, fallback TTL |
| `--cache-expiration-time-custom K=V` | Per-status TTL (e.g. 404=0s) |
| `--browser-cache-expiration-time SEC` | Browser cache TTL |
| `--ignore-query-string` | Cache ignoring query params |
| `--query-params-whitelist` | Only these params differentiate cache |
| `--query-params-blacklist` | These params ignored in cache key |
| `--ignore-cookie` | Cache even with cookies |
| `--slice` | Slice large files into 10MB chunks |
| **Compression** | |
| `--fetch-compressed` | Request compressed from origin |
| `--gzip-on` | Compress with gzip at CDN edge |
| `--brotli-compression TYPES` | Compress with brotli for content-types |
| **Redirects** | |
| `--redirect-http-to-https` | Force HTTPS |
| `--redirect-https-to-http` | Force HTTP |
| **Headers** | |
| `--host-header HOST` | Override Host header to origin |
| `--forward-host-header` | Forward client Host header |
| `--static-headers K=V` | Add response headers |
| `--static-request-headers K=V` | Add request headers to origin |
| `--cors VALS` | CORS Access-Control-Allow-Origin |
| `--cache-http-headers H1,H2` | Cache these response headers |
| **Security** | |
| `--secure-key KEY` | URL signing key |
| `--enable-ip-url-signing` | Restrict signed URLs to IP |
| `--policy-type allow\|deny` | IP ACL policy |
| `--acl-excepted-values CIDR,...` | IP ACL list |
| **Other** | |
| `--allowed-http-methods` | Allowed methods (GET,HEAD,POST,...) |
| `--stale ERRORS` | Serve stale on errors |
| `--rewrite-flag FLAG` | URL rewrite mode (last,break,redirect,permanent) |
| `--rewrite-body PATTERN` | URL rewrite regex |

### Examples

```bash
# CDN for static site from S3 bucket with HTTPS
yc cdn resource create cdn.example.com \
  --origin-bucket-source my-bucket.storage.yandexcloud.net \
  --origin-bucket-name my-bucket \
  --origin-protocol https \
  --lets-encrypt-gcore-ssl-cert \
  --cache-expiration-time 86400 \
  --redirect-http-to-https

# CDN for API with custom origin and short cache
yc cdn resource create api-cdn.example.com \
  --origin-custom-source api.example.com \
  --origin-protocol match \
  --cert-manager-ssl-cert-id <CERT-ID> \
  --cache-expiration-time 60 \
  --ignore-cookie \
  --forward-host-header

# CDN with gzip and CORS
yc cdn resource create static.example.com \
  --origin-group-id <OG-ID> \
  --gzip-on \
  --cors '*' \
  --cache-expiration-time 604800 \
  --browser-cache-expiration-time 86400
```

## Cache Management

```bash
# Purge specific paths
yc cdn cache purge --resource-id <ID> --path "/css/*" --path "/js/*"

# Purge everything
yc cdn cache purge --resource-id <ID> --path "/*"

# Prefetch content (warm cache)
yc cdn cache prefetch --resource-id <ID> --path "/images/hero.jpg" --path "/video/promo.mp4"
```

## DNS Setup

After creating a CDN resource, add a CNAME record:

```bash
PROVIDER_CNAME=$(yc cdn resource get-provider-cname --format json | jq -r .cname)
yc dns zone add-records --name my-zone \
  --record "cdn.example.com. 600 CNAME $PROVIDER_CNAME."
```
