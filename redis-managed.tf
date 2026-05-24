resource "random_password" "managed_redis_password" {
  length  = 24
  special = false
}

resource "yandex_mdb_redis_cluster" "managed" {
  folder_id   = local.folder_id
  name        = var.managed_redis_name
  description = "Managed Redis for Sentry"
  environment = "PRODUCTION"
  network_id  = local.network_id

  config {
    version  = var.managed_redis_version
    password = local.managed_redis_password_effective

    backup_window_start {
      hours   = 3
      minutes = 0
    }
  }

  resources {
    resource_preset_id = var.managed_redis_resource_preset_id
    disk_type_id       = var.managed_redis_disk_type_id
    disk_size          = var.managed_redis_disk_size
  }

  dynamic "host" {
    for_each = toset(local.managed_redis_zones)
    content {
      zone      = host.value
      subnet_id = local.managed_redis_zone_subnet_ids[host.value]
    }
  }

  deletion_protection = false
}

locals {
  managed_redis_password_effective = var.managed_redis_password != "" ? var.managed_redis_password : random_password.managed_redis_password.result

  managed_redis_zones = [
    local.subnet_a_zone,
    local.subnet_b_zone,
    local.subnet_d_zone,
  ]

  managed_redis_zone_subnet_ids = {
    (local.subnet_a_zone) = local.subnet_a_id
    (local.subnet_b_zone) = local.subnet_b_id
    (local.subnet_d_zone) = local.subnet_d_id
  }

  managed_redis_host = yandex_mdb_redis_cluster.managed.host[0].fqdn
}

output "managed_redis_cluster_id" {
  value = yandex_mdb_redis_cluster.managed.id
}

output "managed_redis_host" {
  value = local.managed_redis_host
}

output "managed_redis_user" {
  value = var.managed_redis_user
}

output "managed_redis_password" {
  value     = local.managed_redis_password_effective
  sensitive = true
}

output "managed_redis_port" {
  value = 6379
}
