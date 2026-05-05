resource "random_password" "clickhouse_sentry_password" {
  length  = 24
  special = false
}

resource "local_file" "write_clickhouse_installation" {
  content = templatefile("${path.module}/k8s/clickhouse/clickhouse-installation.yaml.tpl", {
    clickhouse_sentry_password_sha256 = sha256(random_password.clickhouse_sentry_password.result)
  })
  filename        = "${path.module}/k8s/clickhouse/clickhouse-installation.yaml"
  file_permission = "0644"
}

output "clickhouse_sentry_password" {
  description = "Auto-generated password for ClickHouse user 'sentry'"
  value       = random_password.clickhouse_sentry_password.result
  sensitive   = true
}

output "clickhouse_sentry_endpoint" {
  description = "ClickHouse TCP endpoint for Snuba (inside k8s cluster)"
  value       = "chi-sentry-clickhouse-sentry-clickhouse-0-0.clickhouse.svc.cluster.local:9000"
}

output "clickhouse_sentry_http_endpoint" {
  description = "ClickHouse HTTP endpoint (inside k8s cluster)"
  value       = "chi-sentry-clickhouse-sentry-clickhouse-0-0.clickhouse.svc.cluster.local:8123"
}
