resource "random_password" "managed_pg_user_password" {
  length  = 24
  special = false
}

resource "yandex_mdb_postgresql_cluster" "managed" {
  count       = var.managed_pg_enabled ? 1 : 0
  folder_id   = local.folder_id
  name        = var.managed_pg_name
  description = "Managed PostgreSQL for Sentry"
  environment = "PRODUCTION"
  network_id  = local.network_id

  config {
    version = var.managed_pg_version

    resources {
      resource_preset_id = var.managed_pg_resource_preset_id
      disk_type_id       = var.managed_pg_disk_type_id
      disk_size          = var.managed_pg_disk_size
    }

    pooler_config {
      pooling_mode = "TRANSACTION"
    }
  }

  dynamic "host" {
    for_each = toset(local.managed_pg_zones)
    content {
      zone      = host.value
      name      = "sentry-pg-${host.value}"
      subnet_id = local.managed_pg_zone_subnet_ids[host.value]
    }
  }

  deletion_protection = false
}

resource "yandex_mdb_postgresql_user" "sentry" {
  count      = var.managed_pg_enabled ? 1 : 0
  cluster_id = yandex_mdb_postgresql_cluster.managed[0].id
  name       = var.managed_pg_user
  password   = local.managed_pg_user_password_effective
  conn_limit = var.managed_pg_conn_limit
}

resource "yandex_mdb_postgresql_database" "sentry" {
  count      = var.managed_pg_enabled ? 1 : 0
  cluster_id = yandex_mdb_postgresql_cluster.managed[0].id
  name       = var.managed_pg_database
  owner      = yandex_mdb_postgresql_user.sentry[0].name
  lc_collate = "en_US.UTF-8"
  lc_type    = "en_US.UTF-8"

  depends_on = [yandex_mdb_postgresql_user.sentry]
}

locals {
  managed_pg_user_password_effective = var.managed_pg_user_password != "" ? var.managed_pg_user_password : random_password.managed_pg_user_password.result

  managed_pg_zones = [
    local.subnet_a_zone,
    local.subnet_b_zone,
    local.subnet_d_zone,
  ]

  managed_pg_zone_subnet_ids = {
    (local.subnet_a_zone) = local.subnet_a_id
    (local.subnet_b_zone) = local.subnet_b_id
    (local.subnet_d_zone) = local.subnet_d_id
  }

  managed_pg_host = var.managed_pg_enabled ? yandex_mdb_postgresql_cluster.managed[0].host[0].fqdn : ""
}

output "managed_pg_cluster_id" {
  value = var.managed_pg_enabled ? yandex_mdb_postgresql_cluster.managed[0].id : null
}

output "managed_pg_host" {
  value = local.managed_pg_host
}

output "managed_pg_user" {
  value = var.managed_pg_user
}

output "managed_pg_password" {
  value     = local.managed_pg_user_password_effective
  sensitive = true
}

output "managed_pg_database" {
  value = var.managed_pg_database
}

output "managed_pg_port" {
  value = 6432
}
