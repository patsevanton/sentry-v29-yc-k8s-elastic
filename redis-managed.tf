# resource "random_password" "managed_redis_password" {
#   length  = 24
#   special = false
# }

# resource "yandex_mdb_redis_cluster" "managed" {
#   folder_id   = local.folder_id
#   name        = var.managed_redis_name
#   description = "Managed Redis for Sentry"
#   environment = "PRODUCTION"
#   network_id  = local.network_id

#   config {
#     version  = "9.1-valkey"
#     password = local.managed_redis_password_effective

#     backup_window_start {
#       hours   = 3
#       minutes = 0
#     }
#   }

#   resources {
#     resource_preset_id = "hm3-c2-m8"
#     disk_type_id       = "network-ssd"
#     disk_size          = 16
#   }

#   dynamic "host" {
#     for_each = toset(local.managed_redis_zones)
#     content {
#       zone      = host.value
#       subnet_id = local.managed_redis_zone_subnet_ids[host.value]
#     }
#   }

#   deletion_protection = false
# }

# locals {
#   managed_redis_password_effective = var.managed_redis_password != "" ? var.managed_redis_password : random_password.managed_redis_password.result

#   managed_redis_zones = [
#     local.subnet_a_zone,
#     local.subnet_b_zone,
#     local.subnet_d_zone,
#   ]

#   managed_redis_zone_subnet_ids = {
#     (local.subnet_a_zone) = local.subnet_a_id
#     (local.subnet_b_zone) = local.subnet_b_id
#     (local.subnet_d_zone) = local.subnet_d_id
#   }

#   managed_redis_host = yandex_mdb_redis_cluster.managed.host[0].fqdn
# }
