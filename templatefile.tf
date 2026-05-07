resource "local_file" "write_sentry_config" {
  content         = local.sentry_config
  filename        = var.sentry_values_output_path
  file_permission = "0644"
}

locals {
  sentry_admin_password = "admin"

  managed_kafka_user_password_effective = var.managed_kafka_user_password != "" ? var.managed_kafka_user_password : random_password.managed_kafka_user_password.result

  external_clickhouse_effective = {
    host                   = "clickhouse-sentry-clickhouse.clickhouse.svc.cluster.local"
    tcpPort                = 9000
    httpPort               = 8123
    username               = "default"
    password               = ""
    database               = "sentry"
    singleNode             = false
    clusterName            = "sentry-cluster"
    distributedClusterName = "sentry-cluster"
    secure                 = false
  }

  managed_kafka_broker_hosts = sort([for h in yandex_mdb_kafka_cluster.managed.host : h.name])
  external_kafka_effective = {
    cluster = [for host in local.managed_kafka_broker_hosts : {
      host = host
      port = var.managed_kafka_port
    }]
    sasl = {
      mechanism = var.managed_kafka_sasl_mechanism
      username  = var.managed_kafka_user
      password  = local.managed_kafka_user_password_effective
    }
    security = {
      protocol = var.managed_kafka_security_protocol
    }
    provisioning = {
      enabled           = var.external_kafka_provisioning_enabled
      replicationFactor = var.external_kafka_provisioning_replication_factor
      numPartitions     = var.external_kafka_provisioning_num_partitions
    }
  }

  sentry_config = templatefile("${path.module}/values_sentry.yaml.tpl", {
    sentry_admin_password = local.sentry_admin_password
    user_email            = "admin@sentry.local"
    system_url            = "http://sentry.apatsev.org.ru"
    ingress_enabled       = true
    ingress_hostname      = "sentry.apatsev.org.ru"
    ingress_class_name    = "nginx"

    filestore = {
      s3 = {
        accessKey  = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.access_key
        secretKey  = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.secret_key
        bucketName = yandex_storage_bucket.sentry_filestore.bucket
      }
    }

    postgresql_enabled = true
    redis_enabled      = true
    kafka_enabled      = var.sentry_incluster_kafka_enabled
    external_kafka     = local.external_kafka_effective

    external_clickhouse                  = local.external_clickhouse_effective
    sentry_hooks_active_deadline_seconds = var.sentry_hooks_active_deadline_seconds
  })
}
