# Managed ClickHouse в Yandex Cloud (основной сценарий).

resource "random_password" "managed_clickhouse_user_password" {
  length  = 24
  special = false
}

resource "yandex_mdb_clickhouse_cluster" "managed" {
  folder_id   = local.folder_id
  name        = var.managed_clickhouse_name
  description = "Managed ClickHouse for Sentry/Snuba"
  environment = "PRODUCTION"
  network_id  = yandex_vpc_network.sentry.id
  version     = var.managed_clickhouse_version

  clickhouse {
    resources {
      resource_preset_id = var.managed_clickhouse_resource_preset_id
      disk_type_id       = var.managed_clickhouse_disk_type_id
      disk_size          = var.managed_clickhouse_disk_size
    }
  }

  host {
    type      = "CLICKHOUSE"
    zone      = yandex_vpc_subnet.sentry-a.zone
    subnet_id = yandex_vpc_subnet.sentry-a.id
  }

  host {
    type      = "CLICKHOUSE"
    zone      = yandex_vpc_subnet.sentry-b.zone
    subnet_id = yandex_vpc_subnet.sentry-b.id
  }

  host {
    type      = "CLICKHOUSE"
    zone      = yandex_vpc_subnet.sentry-d.zone
    subnet_id = yandex_vpc_subnet.sentry-d.id
  }

  deletion_protection = false
}

resource "yandex_mdb_clickhouse_database" "managed_sentry" {
  cluster_id = yandex_mdb_clickhouse_cluster.managed.id
  name       = var.managed_clickhouse_database
}

resource "time_sleep" "managed_sentry_database_ready" {
  depends_on = [yandex_mdb_clickhouse_database.managed_sentry]

  # YC API can return eventual-consistency NotFound for a just-created database.
  create_duration = "30s"
}

resource "yandex_mdb_clickhouse_user" "managed_sentry" {
  cluster_id = yandex_mdb_clickhouse_cluster.managed.id
  name       = var.managed_clickhouse_user
  password   = local.managed_clickhouse_user_password_effective
  depends_on = [time_sleep.managed_sentry_database_ready]

  permission {
    database_name = yandex_mdb_clickhouse_database.managed_sentry.name
  }
}

output "external_clickhouse_host" {
  description = "Effective external ClickHouse host used in generated values_sentry.yaml"
  value       = local.external_clickhouse_effective.host
}

output "external_clickhouse_tcp_port" {
  description = "Effective external ClickHouse TCP port used in generated values_sentry.yaml"
  value       = local.external_clickhouse_effective.tcpPort
}

output "external_clickhouse_http_port" {
  description = "Effective external ClickHouse HTTP port used in generated values_sentry.yaml"
  value       = local.external_clickhouse_effective.httpPort
}

output "external_clickhouse_username" {
  description = "Effective external ClickHouse username used in generated values_sentry.yaml"
  value       = local.external_clickhouse_effective.username
}

output "external_clickhouse_password" {
  description = "Effective external ClickHouse password used in generated values_sentry.yaml"
  value       = local.external_clickhouse_effective.password
  sensitive   = true
}

output "external_clickhouse_database" {
  description = "Effective external ClickHouse database used in generated values_sentry.yaml"
  value       = local.external_clickhouse_effective.database
}

output "external_clickhouse_cluster_name" {
  description = "Effective external ClickHouse clusterName used in generated values_sentry.yaml"
  value       = var.external_clickhouse_cluster_name
}

output "external_clickhouse_distributed_cluster_name" {
  description = "Effective external ClickHouse distributedClusterName used in generated values_sentry.yaml"
  value       = var.external_clickhouse_distributed_cluster_name
}

output "enable_clickhouse_dns_search" {
  description = "Whether clickhouse DNS search suffix is enabled in generated values_sentry.yaml"
  value       = var.enable_clickhouse_dns_search
}

output "clickhouse_dns_search_suffix" {
  description = "Clickhouse DNS search suffix used in generated values_sentry.yaml"
  value       = var.clickhouse_dns_search_suffix
}

output "managed_clickhouse_cluster_id" {
  description = "Managed ClickHouse cluster ID"
  value       = yandex_mdb_clickhouse_cluster.managed.id
}

output "managed_clickhouse_hosts" {
  description = "Managed ClickHouse host FQDNs"
  value       = [for h in yandex_mdb_clickhouse_cluster.managed.host : h.fqdn]
}
