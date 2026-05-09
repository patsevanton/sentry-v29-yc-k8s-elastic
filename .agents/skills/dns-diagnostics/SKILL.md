---
name: dns-diagnostics
description: >-
  Comprehensive DNS diagnostic playbook for Kubernetes clusters — CoreDNS, NodeLocalDNS,
  NetworkPolicy, and resolution paths. Adapted for Yandex Cloud Managed Kubernetes.
---

# DNS Diagnostics Playbook

When a user reports DNS resolution failures, follow this flow to identify the root cause.

**Scope:** This skill is for **diagnosis only**. Once you identify the root cause, report it to the user and stop. Do NOT attempt to fix the issue unless explicitly asked.

Use this skill when the user's question involves:

- Pods failing to resolve service names or external domains
- `Name or service not known`, `NXDOMAIN`, `SERVFAIL` errors
- Intermittent DNS failures
- Service unreachable by name but reachable by IP
- Questions about CoreDNS or NodeLocalDNS health

## Project Context

This project runs Sentry on Yandex Cloud Managed Kubernetes. Key namespaces:
- `sentry` — Sentry application (web, worker, cron, kafka consumer)
- `clickhouse` — ClickHouse cluster (clickhouse-operator)
- `vmks` — VictoriaMetrics monitoring stack
- `keda` — KEDA autoscaler
- `kube-system` — CoreDNS, system components

## Diagnostic Evidence Collection

Run these checks in order. Record the exact command and a one-line summary
of each result into the evidence table.

### Step 1 — CoreDNS pod health

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl describe deploy coredns -n kube-system
```

Check:
- All pods `Ready=True`
- No recent restarts (`RESTARTS` column)
- Deployment replica count matches desired

### Step 2 — CoreDNS service + endpoints

```bash
kubectl get svc kube-dns -n kube-system
kubectl get endpointslices -n kube-system -l k8s-app=kube-dns
```

Check:
- Service has ClusterIP
- EndpointSlice lists all CoreDNS pod IPs
- No endpoints missing

### Step 3 — CoreDNS configuration

```bash
kubectl get configmap coredns -n kube-system -o yaml
```

Look for:
- `forward` directive pointing somewhere valid (usually `/etc/resolv.conf`)
- `cache` block present (default 30s)
- Custom rewrite rules that may be broken
- `loop` plugin present (detects forwarding loops)

### Step 4 — CoreDNS logs for the last 5 minutes

```bash
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=200 --since=5m
```

Look for:
- `plugin/errors` entries showing upstream failures
- High rates of `SERVFAIL` or `REFUSED`
- Cache hit/miss ratio (if Prometheus plugin output is logged)

### Step 5 — CoreDNS metrics

```bash
kubectl get --raw /api/v1/namespaces/kube-system/services/http:kube-dns:metrics/proxy/metrics | grep -E 'coredns_dns_request_count|coredns_plugin_enabled|coredns_cache_hits'
```

Compute error rate:
- `sum(rate(coredns_dns_requests_total{rcode!="NOERROR"}[5m])) / sum(rate(coredns_dns_requests_total[5m]))`
- Anything > 5% is concerning.

### Step 6 — DNS resolution test from affected pod

```bash
# Internal (cluster.local)
kubectl -n sentry exec -it deploy/sentry-web -- nslookup kubernetes.default.svc.cluster.local

# Sentry services
kubectl -n sentry exec -it deploy/sentry-web -- nslookup sentry-web.sentry.svc.cluster.local
kubectl -n sentry exec -it deploy/sentry-web -- nslookup sentry-clickhouse.clickhouse.svc.cluster.local

# External
kubectl -n sentry exec -it deploy/sentry-web -- nslookup www.google.com
```

Note: DNS policy of the test pod may differ from the affected pod.
Always record `kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.dnsPolicy}'`.

### Step 7 — NetworkPolicy blocking DNS

```bash
kubectl get networkpolicy -A
```

Look for:
- Policies in the affected namespace with `policyTypes: [Egress]`
- Egress rules that don't include port 53 UDP/TCP or the kube-dns endpoint

### Step 8 — NodeLocalDNS (if deployed)

```bash
kubectl get ds -n kube-system -l k8s-app=node-local-dns
kubectl logs -n kube-system -l k8s-app=node-local-dns --tail=50 --since=5m
```

Check:
- DaemonSet pods running on every node
- Interface `169.254.20.10` (or whatever the NodeLocalDNS IP is)
- LocalRedirectPolicy present (if required by CNI)

## Failure Patterns & Root Causes

| Pattern | Evidence | Likely Root Cause |
|---|---|---|
| All pods can't resolve anything | Step 1 or 2 fails | CoreDNS down or no endpoints |
| Some pods resolve, others don't | Step 6 inconsistent | NetworkPolicy / node affinity / DNS policy difference |
| External names fail, internal works | Step 6 external fails | Upstream DNS misconfig in CoreDNS forward |
| `SERVFAIL` in logs | Step 4 | Upstream DNS unreachable (check forward directive in Step 3) |
| Intermittent failures | Step 5 high error rate | CoreDNS capacity / caching issue, or upstream flaky |
| Resolution works in some namespaces only | Step 7 | NetworkPolicy blocking DNS egress |
| NodeLocalDNS-specific failures | Step 8 | Missing LocalRedirectPolicy |
| Custom domain not resolving | Step 3 `rewrite` or `forward` | Misconfigured ConfigMap |
| Kafka/ClickHouse/Sentry can't find each other | Step 6 with specific svc name | Wrong namespace or service name in config |

## Proposed Remediation Examples

| Root Cause | Remediation | Priority |
|---|---|---|
| CoreDNS crashlooping | `kubectl rollout restart deployment/coredns -n kube-system` | T0 |
| NetworkPolicy missing DNS egress | Apply patched NetworkPolicy with port 53 UDP/TCP | T2 (staging), T3 (prod) |
| CoreDNS ConfigMap malformed | `kubectl edit configmap coredns -n kube-system` | T3 |
| NodeLocalDNS pods missing | `kubectl rollout restart daemonset/node-local-dns -n kube-system` | T0 |
| Upstream DNS server unreachable | Investigate Yandex Cloud DNS / NAT gateway | T4 (escalate) |
| Service name wrong in Sentry config | Fix `values_sentry.yaml.tpl` and re-run `terraform apply` | T1 |

## Ambiguity Handling

If after running steps 1-8 the evidence doesn't point clearly to one root cause:

1. Set `status: "insufficient_data"` in the output
2. List the specific additional data needed in `human_summary`
3. Suggest the user provide:
   - Specific pod/namespace that's affected
   - Exact error message they see
   - Whether it's consistent or intermittent
   - Whether it affects internal or external names

Never guess — escalate to a human.
