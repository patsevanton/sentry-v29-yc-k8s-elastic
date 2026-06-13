resource "local_file" "write_sentry_config" {
  content         = local.sentry_config
  filename        = "values_sentry.yaml"
  file_permission = "0644"
}

locals {
  sentry_admin_password = "admin"

  # managed_kafka_user_password_effective = var.managed_kafka_user_password != "" ? var.managed_kafka_user_password : random_password.managed_kafka_user_password.result
  managed_kafka_user_password_effective = var.managed_kafka_user_password

  external_clickhouse_effective = {
    host                   = "clickhouse-sentry-clickhouse.clickhouse.svc.cluster.local"
    tcpPort                = 9000
    httpPort               = 8123
    username               = "default"
    password               = ""
    database               = "default"
    singleNode             = false
    clusterName            = "sentry-cluster"
    distributedClusterName = "sentry-cluster"
    secure                 = false
  }

  kafka_credentials_secret_name = "kafka-credentials"

  # managed_kafka_broker_hosts      = sort([for h in yandex_mdb_kafka_cluster.managed.host : h.name])
  managed_kafka_broker_hosts      = []
  managed_kafka_bootstrap_servers = join(",", [for host in local.managed_kafka_broker_hosts : "${host}:${var.managed_kafka_port}"])
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
      protocol = "SASL_PLAINTEXT"
    }
    provisioning = {
      enabled           = var.external_kafka_provisioning_enabled
      replicationFactor = 3
      numPartitions     = 3
    }
  }

  sentry_config = templatefile("${path.module}/values_sentry.yaml.tpl", {
    sentry_admin_password         = local.sentry_admin_password
    user_email                    = "admin@sentry.local"
    system_url                    = "http://sentry.apatsev.org.ru"
    ingress_enabled               = true
    ingress_hostname              = "sentry.apatsev.org.ru"
    ingress_class_name            = "nginx"
    kafka_credentials_secret_name = local.kafka_credentials_secret_name

    filestore = {
      s3 = {
        accessKey  = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.access_key
        secretKey  = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.secret_key
        bucketName = yandex_storage_bucket.sentry_filestore.bucket
      }
    }

    postgresql_enabled = false
    redis_enabled      = true

    external_redis_enabled = false
    # external_redis = {
    #   host     = local.managed_redis_host
    #   port     = 6379
    #   username = var.managed_redis_user
    #   password = local.managed_redis_password_effective
    #   ssl      = false
    # }
    external_redis = {
      host     = ""
      port     = 6379
      username = ""
      password = ""
      ssl      = false
    }

    external_postgresql_enabled = true
    external_postgresql = {
      host     = local.managed_pg_host
      port     = 6432
      username = var.managed_pg_user
      password = local.managed_pg_user_password_effective
      database = var.managed_pg_database
      sslmode  = "require"
    }
    kafka_enabled      = var.sentry_incluster_kafka_enabled
    external_kafka     = local.external_kafka_effective

    external_clickhouse                  = local.external_clickhouse_effective
    sentry_hooks_active_deadline_seconds = 7200
  })

  # kafka_credentials_config = templatefile("${path.module}/k8s/kafka-credentials.yaml.tpl", {
  #   secret_name = local.kafka_credentials_secret_name
  #   mechanism   = var.managed_kafka_sasl_mechanism
  #   username    = var.managed_kafka_user
  #   password    = local.managed_kafka_user_password_effective
  # })

  managed_pg_credentials_config = templatefile("${path.module}/k8s/managed-pg-credentials.yaml.tpl", {
    secret_name = "managed-pg-credentials"
    password    = local.managed_pg_user_password_effective
  })

  # managed_redis_credentials_config = templatefile("${path.module}/k8s/managed-redis-credentials.yaml.tpl", {
  #   secret_name = "managed-redis-credentials"
  #   password    = local.managed_redis_password_effective
  # })
}

# resource "local_file" "write_kafka_credentials" {
#   content         = local.kafka_credentials_config
#   filename        = "${path.module}/k8s/kafka-credentials.yaml"
#   file_permission = "0600"
# }

resource "local_file" "write_managed_pg_credentials" {
  content         = local.managed_pg_credentials_config
  filename        = "${path.module}/k8s/managed-pg-credentials.yaml"
  file_permission = "0600"
}

# resource "local_file" "write_managed_redis_credentials" {
#   content         = local.managed_redis_credentials_config
#   filename        = "${path.module}/k8s/managed-redis-credentials.yaml"
#   file_permission = "0600"
# }

