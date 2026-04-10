resource "random_password" "managed_clickhouse_user_password" {
  length  = 24
  special = false
}

resource "random_password" "managed_clickhouse_admin_password" {
  count   = var.managed_clickhouse_sql_user_management_enabled && var.managed_clickhouse_admin_password == "" ? 1 : 0
  length  = 24
  special = false
}

resource "yandex_mdb_clickhouse_cluster" "managed" {
  folder_id           = local.folder_id
  name                = var.managed_clickhouse_name
  description         = "Managed ClickHouse for Sentry/Snuba"
  environment         = "PRODUCTION"
  network_id          = local.network_id
  version             = var.managed_clickhouse_version
  sql_user_management = var.managed_clickhouse_sql_user_management_enabled
  admin_password      = var.managed_clickhouse_sql_user_management_enabled ? local.managed_clickhouse_admin_password_effective : null

  clickhouse {
    resources {
      resource_preset_id = var.managed_clickhouse_resource_preset_id
      disk_type_id       = var.managed_clickhouse_disk_type_id
      disk_size          = var.managed_clickhouse_disk_size
    }
  }

  host {
    type             = "CLICKHOUSE"
    zone             = local.subnet_a_zone
    subnet_id        = local.subnet_a_id
    assign_public_ip = true
  }

  host {
    type             = "CLICKHOUSE"
    zone             = local.subnet_b_zone
    subnet_id        = local.subnet_b_id
    assign_public_ip = true
  }

  host {
    type             = "CLICKHOUSE"
    zone             = local.subnet_d_zone
    subnet_id        = local.subnet_d_id
    assign_public_ip = true
  }

  deletion_protection = false
}

resource "yandex_mdb_clickhouse_database" "managed_sentry" {
  cluster_id = yandex_mdb_clickhouse_cluster.managed.id
  name       = var.managed_clickhouse_database
}

resource "time_sleep" "managed_sentry_database_ready" {
  depends_on      = [yandex_mdb_clickhouse_database.managed_sentry]
  create_duration = "30s"
}

resource "yandex_mdb_clickhouse_user" "managed_sentry" {
  count      = var.managed_clickhouse_sql_user_management_enabled ? 0 : 1
  cluster_id = yandex_mdb_clickhouse_cluster.managed.id
  name       = var.managed_clickhouse_user
  password   = local.managed_clickhouse_user_password_effective
  depends_on = [time_sleep.managed_sentry_database_ready]

  permission {
    database_name = yandex_mdb_clickhouse_database.managed_sentry.name
  }
}

# provider "clickhousedbops" {
#   host     = yandex_mdb_clickhouse_cluster.managed.host[0].fqdn
#   port     = var.external_clickhouse_tcp_port
#   protocol = "nativesecure"
#
#   auth_config = {
#     strategy = "password"
#     username = "admin"
#     password = local.managed_clickhouse_admin_password_effective
#   }
# }
#
# resource "clickhousedbops_user" "managed_sentry" {
#   count                = var.managed_clickhouse_sql_user_management_enabled ? 1 : 0
#   name                 = var.managed_clickhouse_user
#   password_sha256_hash = sha256(local.managed_clickhouse_user_password_effective)
#
#   depends_on = [
#     yandex_mdb_clickhouse_cluster.managed,
#     yandex_mdb_clickhouse_database.managed_sentry,
#     time_sleep.managed_sentry_database_ready
#   ]
# }
#
# resource "clickhousedbops_grant_privilege" "managed_sentry_db_all" {
#   count             = var.managed_clickhouse_sql_user_management_enabled ? 1 : 0
#   privilege_name    = "ALL"
#   database_name     = yandex_mdb_clickhouse_database.managed_sentry.name
#   grantee_user_name = clickhousedbops_user.managed_sentry[0].name
#   depends_on        = [clickhousedbops_user.managed_sentry]
# }
#
# resource "clickhousedbops_grant_privilege" "managed_sentry_create_workload" {
#   count             = var.managed_clickhouse_sql_user_management_enabled && var.managed_clickhouse_grant_create_workload ? 1 : 0
#   privilege_name    = "CREATE WORKLOAD"
#   grantee_user_name = clickhousedbops_user.managed_sentry[0].name
#   depends_on        = [clickhousedbops_user.managed_sentry]
# }

output "external_clickhouse_host" {
  value = local.external_clickhouse_effective.host
}

output "external_clickhouse_tcp_port" {
  value = local.external_clickhouse_effective.tcpPort
}

output "external_clickhouse_http_port" {
  value = local.external_clickhouse_effective.httpPort
}

output "external_clickhouse_username" {
  value = local.external_clickhouse_effective.username
}

output "external_clickhouse_password" {
  value     = local.external_clickhouse_effective.password
  sensitive = true
}

output "external_clickhouse_database" {
  value = local.external_clickhouse_effective.database
}

output "external_clickhouse_cluster_name" {
  value = var.external_clickhouse_cluster_name
}

output "external_clickhouse_distributed_cluster_name" {
  value = var.external_clickhouse_distributed_cluster_name
}

output "enable_clickhouse_dns_search" {
  value = var.enable_clickhouse_dns_search
}

output "clickhouse_dns_search_suffix" {
  value = var.clickhouse_dns_search_suffix
}

output "managed_clickhouse_cluster_id" {
  value = yandex_mdb_clickhouse_cluster.managed.id
}

output "managed_clickhouse_hosts" {
  value = [for h in yandex_mdb_clickhouse_cluster.managed.host : h.fqdn]
}

output "managed_clickhouse_admin_password" {
  value     = local.managed_clickhouse_admin_password_effective
  sensitive = true
}
