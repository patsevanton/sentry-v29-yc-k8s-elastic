resource "null_resource" "write_sentry_config" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p "$(dirname "${var.sentry_values_output_path}")"
      cat > "${var.sentry_values_output_path}" <<'EOF'
      ${local.sentry_config}
      EOF
    EOT
  }

  triggers = {
    sentry_config             = local.sentry_config
    sentry_values_output_path = var.sentry_values_output_path
  }
}

locals {
  sentry_admin_password = "admin"

  managed_clickhouse_user_password_effective  = var.managed_clickhouse_user_password != "" ? var.managed_clickhouse_user_password : random_password.managed_clickhouse_user_password.result
  managed_clickhouse_admin_password_effective = var.managed_clickhouse_admin_password != "" ? var.managed_clickhouse_admin_password : one(random_password.managed_clickhouse_admin_password[*].result)
  managed_kafka_user_password_effective       = var.managed_kafka_user_password != "" ? var.managed_kafka_user_password : random_password.managed_kafka_user_password.result

  # Yandex MCH: Snuba ON CLUSTER must match system.clusters.cluster. In Yandex Cloud that name is
  # typically "default", not yandex_mdb_clickhouse_cluster.<name> (API resource name).
  external_clickhouse_cluster_name_effective = (
    var.external_clickhouse_cluster_name != "" ?
    var.external_clickhouse_cluster_name :
    var.managed_clickhouse_clickhouse_cluster_name
  )
  external_clickhouse_distributed_cluster_name_effective = (
    var.external_clickhouse_distributed_cluster_name != "" ?
    var.external_clickhouse_distributed_cluster_name :
    var.managed_clickhouse_clickhouse_cluster_name
  )

  external_clickhouse_effective = {
    host                   = yandex_mdb_clickhouse_cluster.managed.host[0].fqdn
    tcpPort                = var.external_clickhouse_tcp_port
    httpPort               = var.external_clickhouse_http_port
    username               = var.managed_clickhouse_user
    password               = local.managed_clickhouse_user_password_effective
    database               = var.managed_clickhouse_database
    singleNode             = var.external_clickhouse_single_node
    clusterName            = local.external_clickhouse_cluster_name_effective
    distributedClusterName = local.external_clickhouse_distributed_cluster_name_effective
    secure                 = true
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

    sentry_image_repository = "ghcr.io/patsevanton/sentry-v29-yc-k8s-elastic"
    sentry_image_tag        = "sentry-1.25.0"
    snuba_image_repository  = "ghcr.io/patsevanton/sentry-v29-yc-k8s-elastic"
    snuba_image_tag         = "snuba-1.25.0"

    elasticsearch_url = "http://sentry-nodestore-es-http.elasticsearch.svc.cluster.local:9200"

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
    enable_clickhouse_dns_search         = var.enable_clickhouse_dns_search
    clickhouse_dns_search_suffix         = var.clickhouse_dns_search_suffix
  })
}
