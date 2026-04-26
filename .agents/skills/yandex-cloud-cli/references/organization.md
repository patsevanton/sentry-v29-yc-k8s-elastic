# Organization, Security, Quotas, IoT (yc organization-manager, yc smartwebsecurity, yc smartcaptcha, yc quota-manager, yc iot)

## Organization Manager (yc organization-manager)

### Organizations

```
yc organization-manager organization list
yc organization-manager organization get <NAME|ID>
yc organization-manager organization list-access-bindings --id <ORG-ID>
yc organization-manager organization add-access-binding --id <ORG-ID> --role ROLE --subject TYPE:ID
yc organization-manager organization remove-access-binding --id <ORG-ID> --role ROLE --subject TYPE:ID
```

### Users

```
yc organization-manager user list --organization-id <ORG-ID>
yc organization-manager user remove <USER-ID> --organization-id <ORG-ID>
```

### Groups

```
yc organization-manager group list --organization-id <ORG-ID>
yc organization-manager group get <NAME|ID> --organization-id <ORG-ID>
yc organization-manager group create --name NAME --organization-id <ORG-ID>
yc organization-manager group update <NAME|ID> --organization-id <ORG-ID> [flags]
yc organization-manager group delete <NAME|ID> --organization-id <ORG-ID>
yc organization-manager group list-members <NAME|ID> --organization-id <ORG-ID>
yc organization-manager group add-members <NAME|ID> --organization-id <ORG-ID> --subject-id <USER-ID>
yc organization-manager group remove-members <NAME|ID> --organization-id <ORG-ID> --subject-id <USER-ID>
```

### Federations (SSO)

```
yc organization-manager federation saml list --organization-id <ORG-ID>
yc organization-manager federation saml get <NAME|ID> --organization-id <ORG-ID>
yc organization-manager federation saml create [flags]
yc organization-manager federation saml update <NAME|ID> [flags]
yc organization-manager federation saml delete <NAME|ID>
```

### OS Login

```
yc organization-manager oslogin profile list --organization-id <ORG-ID>
yc organization-manager oslogin profile get <PROFILE-ID>
yc organization-manager oslogin profile create [flags]
yc organization-manager oslogin profile delete <PROFILE-ID>
yc organization-manager oslogin user-ssh-key list --organization-id <ORG-ID>
yc organization-manager oslogin user-ssh-key create [flags]
```

---

## Smart Web Security (yc smartwebsecurity / yc sws)

### Security Profiles

```
yc sws security-profile list
yc sws security-profile get <NAME|ID>
yc sws security-profile create <NAME> [flags]
yc sws security-profile update <NAME|ID> [flags]
yc sws security-profile delete <NAME|ID>
```

Create flags:

| Flag | Purpose |
|------|---------|
| `--name NAME` | Profile name |
| `--description TEXT` | Description |
| `--labels K=V,...` | Labels |
| `--default-action ALLOW\|DENY` | Action when no rules match (default: ALLOW) |
| `--captcha-id ID` | SmartCaptcha ID to use (empty = default) |
| `--security-rules-file FILE` | YAML file with security rules array |

### Security Rules (YAML)

Rules are defined in a YAML file passed via `--security-rules-file`. Each rule has a priority (lower = higher precedence), an action type, and conditions.

**Rule types:**

| Type | Purpose |
|------|---------|
| `rule_condition` | Static allow/deny based on conditions |
| `smart_protection` | Dynamic bot detection with optional captcha |

**Condition matchers:**

| Field | Matchers |
|-------|----------|
| `authority.authorities[]` | `exact_match`, `prefix_match`, `pire_regex_match` |
| `http_method.http_methods[]` | `exact_match` |
| `request_uri.path` | `prefix_match`, `exact_match`, `pire_regex_match` |
| `request_uri.queries[]` | `key` + `value.{pire_regex_match, pire_regex_not_match}` |
| `headers[]` | `name` + `value.{pire_regex_match, pire_regex_not_match}` |
| `source_ip.ip_ranges_match.ip_ranges[]` | IP/CIDR list |
| `source_ip.ip_ranges_not_match.ip_ranges[]` | IP/CIDR exclusion |
| `source_ip.geo_ip_match.locations[]` | Country codes (ru, us, etc.) |
| `source_ip.geo_ip_not_match.locations[]` | Country code exclusion |

Example `security-rules.yaml`:
```yaml
# Deny by condition
- name: block-bad-ips
  priority: "1"
  dry_run: false
  rule_condition:
    action: DENY
    condition:
      source_ip:
        ip_ranges_match:
          ip_ranges:
            - 1.2.3.0/24
        geo_ip_not_match:
          locations:
            - ru

# Whitelist trusted IPs
- name: allow-office
  priority: "2"
  rule_condition:
    action: ALLOW
    condition:
      source_ip:
        ip_ranges_match:
          ip_ranges:
            - 44.44.44.44

# Smart protection for web pages (may show captcha)
- name: smart-protection-web
  priority: "10"
  smart_protection:
    mode: FULL
    condition:
      request_uri:
        path:
          prefix_match: /

# Smart protection for API (no captcha, API mode)
- name: smart-protection-api
  priority: "9"
  smart_protection:
    mode: API
    condition:
      request_uri:
        path:
          prefix_match: /api
```

### Attach to ALB

```bash
yc alb virtual-host update my-vh \
  --http-router-name my-router \
  --security-profile-id <PROFILE-ID>
```

### Full Setup Example

```bash
# 1. Create SmartCaptcha (optional, for custom captcha)
CAPTCHA_ID=$(yc smartcaptcha captcha create my-captcha \
  --allowed-site example.com \
  --complexity MEDIUM \
  --pre-check-type CHECKBOX \
  --challenge-type IMAGE_TEXT \
  --format json | jq -r .id)

# 2. Create security profile with rules
yc sws security-profile create my-profile \
  --default-action ALLOW \
  --captcha-id $CAPTCHA_ID \
  --security-rules-file security-rules.yaml

# 3. Attach to ALB virtual host
PROFILE_ID=$(yc sws security-profile get my-profile --format json | jq -r .id)
yc alb virtual-host update my-vh \
  --http-router-name my-router \
  --security-profile-id $PROFILE_ID
```

---

## SmartCaptcha (yc smartcaptcha / yc sc)

### Captcha Management

```
yc smartcaptcha captcha list
yc smartcaptcha captcha get <NAME|ID>
yc smartcaptcha captcha create <NAME> [flags]
yc smartcaptcha captcha update <NAME|ID> [flags]
yc smartcaptcha captcha delete <NAME|ID>
```

### Create / Update Flags

| Flag | Purpose |
|------|---------|
| `--name NAME` | Captcha name |
| `--complexity LEVEL` | `EASY` / `MEDIUM` (default) / `HARD` / `FORCE_HARD` |
| `--pre-check-type TYPE` | `CHECKBOX` (default) / `SLIDER` |
| `--challenge-type TYPE` | `IMAGE_TEXT` (default) / `SILHOUETTES` / `KALEIDOSCOPE` |
| `--allowed-site HOST,...` | Allowed hostnames |
| `--turn-off-hostname-check` | Disable hostname validation |
| `--style-json JSON` | Custom appearance (JSON from console) |
| `--security-rules-file FILE` | Per-page captcha rules (YAML) |
| `--override-variants-file FILE` | Captcha variant overrides (YAML) |

**Complexity levels:**
- `EASY` — high chance to pass pre-check, easy challenge
- `MEDIUM` — balanced (default)
- `HARD` — low chance to pass pre-check, hard challenge
- `FORCE_HARD` — no pre-check pass, hard challenge always

**Challenge types:**
- `IMAGE_TEXT` — type distorted text from image
- `SILHOUETTES` — mark icons in order
- `KALEIDOSCOPE` — assemble picture from parts via slider

### Security Rules (per-page overrides)

Override captcha behavior on specific pages via `--security-rules-file`:

```yaml
- name: hard-captcha-on-login
  priority: "11"
  override_variant_uuid: hard-variant
  condition:
    uri:
      path:
        prefix_match: /login
    source_ip:
      geo_ip_not_match:
        locations:
          - ru
```

Override variants file (`--override-variants-file`):

```yaml
- uuid: hard-variant
  description: Hard captcha for suspicious traffic
  complexity: HARD
  pre_check_type: CHECKBOX
  challenge_type: SILHOUETTES
```

### Example

```bash
# Create captcha for a website
yc smartcaptcha captcha create my-site-captcha \
  --allowed-site example.com,www.example.com \
  --complexity MEDIUM \
  --pre-check-type CHECKBOX \
  --challenge-type IMAGE_TEXT

# Use with Smart Web Security profile
CAPTCHA_ID=$(yc smartcaptcha captcha get my-site-captcha --format json | jq -r .id)
yc sws security-profile create my-profile \
  --default-action ALLOW \
  --captcha-id $CAPTCHA_ID \
  --security-rules-file rules.yaml
```

---

## Quota Manager (yc quota-manager)

### View Quotas

```bash
# List available quota services
yc quota-manager quota-limit list-services --resource-type cloud

# List all quotas for your cloud
yc quota-manager quota-limit list \
  --resource-id <CLOUD-ID> \
  --resource-type cloud

# List quotas for a specific service
yc quota-manager quota-limit list \
  --resource-id <CLOUD-ID> \
  --resource-type cloud \
  --service compute

# Get specific quota details
yc quota-manager quota-limit get \
  --resource-id <CLOUD-ID> \
  --resource-type cloud \
  --quota-id compute.disks.count
```

### Request Quota Increase

```bash
# Request more VMs and disks
yc quota-manager quota-request create \
  --resource-id <CLOUD-ID> \
  --resource-type cloud \
  --desired-limit quota-id=compute.instances.count,value=50 \
  --desired-limit quota-id=compute.disks.count,value=100

# Check request status
yc quota-manager quota-request list \
  --resource-id <CLOUD-ID> \
  --resource-type cloud

yc quota-manager quota-request get <REQUEST-ID>
yc quota-manager quota-request list-operations <REQUEST-ID>

# Cancel pending request
yc quota-manager quota-request cancel <REQUEST-ID> \
  --quota-id compute.instances.count
```

---

## IoT Core (yc iot)

### Registry

```
yc iot registry list
yc iot registry get <NAME|ID>
yc iot registry create --name NAME [--labels K=V]
yc iot registry update <NAME|ID> [flags]
yc iot registry delete <NAME|ID>
yc iot registry add-password <NAME|ID> --password PASS
yc iot registry add-certificate <NAME|ID> --certificate-file FILE
```

### Device

```
yc iot device list --registry-name NAME
yc iot device get <NAME|ID>
yc iot device create --registry-name NAME --name NAME
yc iot device update <NAME|ID> [flags]
yc iot device delete <NAME|ID>
yc iot device add-password <NAME|ID> --password PASS
yc iot device add-certificate <NAME|ID> --certificate-file FILE
```

### MQTT

```bash
# Publish from device
yc iot mqtt publish \
  --device-id <DEVICE-ID> \
  --topic '$devices/<DEVICE-ID>/events' \
  --message '{"temp": 22.5}' \
  --qos 1

# Subscribe (registry level)
yc iot mqtt subscribe \
  --registry-id <REGISTRY-ID> \
  --topic '$registries/<REGISTRY-ID>/events' \
  --qos 1
```
