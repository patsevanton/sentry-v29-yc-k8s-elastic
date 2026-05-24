resource "random_password" "managed_kafka_user_password" {
  length  = 24
  special = false
}

resource "yandex_mdb_kafka_cluster" "managed" {
  folder_id   = local.folder_id
  name        = "sentry-kafka-managed"
  description = "Managed Kafka for Sentry"
  environment = "PRODUCTION"
  network_id  = local.network_id
  subnet_ids  = [local.subnet_a_id, local.subnet_b_id, local.subnet_d_id]

  config {
    version          = "4.0"
    brokers_count    = 1
    zones            = [local.subnet_a_zone, local.subnet_b_zone, local.subnet_d_zone]
    assign_public_ip = var.managed_kafka_assign_public_ip
    # unmanaged_topics = true
    schema_registry  = false

    kafka {
      resources {
        resource_preset_id = "s2.micro"
        disk_type_id       = "network-ssd"
        disk_size          = 32
      }

      kafka_config {
        auto_create_topics_enable = true
        # Держим значение выше максимального max.message.bytes среди топиков
        # в кластере (например snuba-lw-deletions-eap-items=50000000), потому
        # что в multi-node Kafka replica.fetch.max.bytes должен быть >= размера
        # сообщения, иначе API YC отклоняет операции с кластером
        replica_fetch_max_bytes = 67108864
      }
    }
  }

  deletion_protection = false
}

resource "yandex_mdb_kafka_user" "managed_sentry" {
  cluster_id = yandex_mdb_kafka_cluster.managed.id
  name       = var.managed_kafka_user
  password   = local.managed_kafka_user_password_effective

  permission {
    topic_name = "*"
    role       = "ACCESS_ROLE_ADMIN"
  }
}

output "managed_kafka_cluster_id" {
  value = yandex_mdb_kafka_cluster.managed.id
}

output "managed_kafka_hosts" {
  value = sort([for h in yandex_mdb_kafka_cluster.managed.host : h.name])
}

output "managed_kafka_user" {
  value = var.managed_kafka_user
}

output "managed_kafka_password" {
  value     = local.managed_kafka_user_password_effective
  sensitive = true
}

output "managed_kafka_port" {
  value = var.managed_kafka_port
}
