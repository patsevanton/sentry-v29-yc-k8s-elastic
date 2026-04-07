# Ресурс null_resource используется для выполнения локальной команды,
# генерирующей файл конфигурации Sentry на основе шаблона
resource "null_resource" "write_sentry_config" {
  provisioner "local-exec" {
    # Команда записывает сгенерированную строку (YAML) в файл values_sentry.yaml
    command = "echo '${local.sentry_config}' > values_sentry.yaml"
  }

  triggers = {
    # Триггер перезапуска ресурса при изменении содержимого values_sentry.yaml.tpl
    sentry_config = local.sentry_config
  }
}

locals {
  # Пароль администратора Sentry
  sentry_admin_password = "admin"

  # Локальная переменная с конфигурацией Sentry, генерируемая из шаблона values_sentry.yaml.tpl
  sentry_config = templatefile("values_sentry.yaml.tpl", {
    # Пароль администратора Sentry
    sentry_admin_password = local.sentry_admin_password

    # Email пользователя-администратора
    user_email = "admin@sentry.local"

    # URL системы Sentry
    system_url = "http://sentry.apatsev.org.ru"

    # Использование Ingress для доступа к Sentry
    ingress_enabled = true

    # Имя хоста, используемого Ingress
    ingress_hostname = "sentry.apatsev.org.ru"

    # Имя класса Ingress-контроллера
    ingress_class_name = "nginx"

    # Контейнерные образы
    sentry_image_repository = "ghcr.io/patsevanton/sentry-v29-yc-k8s-elastic"
    sentry_image_tag        = "sentry-1.3.0"
    snuba_image_repository  = "ghcr.io/patsevanton/sentry-v29-yc-k8s-elastic"
    snuba_image_tag         = "snuba-1.3.0"

    # URL Elasticsearch для nodestore
    elasticsearch_url = "http://sentry-nodestore-es-http.elasticsearch.svc.cluster.local:9200"

    # Настройки S3-хранилища для файлового хранилища (filestore)
    filestore = {
      s3 = {
        accessKey  = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.access_key
        secretKey  = yandex_iam_service_account_static_access_key.sa_s3_sentry_key.secret_key
        bucketName = yandex_storage_bucket.sentry_filestore.bucket
      }
    }

    # Встроенные компоненты: PostgreSQL, Redis, Kafka — в кластере
    postgresql_enabled = true
    redis_enabled      = true
    kafka_enabled      = true

    # Внешний ClickHouse (Altinity Operator, namespace clickhouse)
    external_clickhouse = {
      host                   = "clickhouse-sentry-clickhouse.clickhouse.svc.cluster.local"
      tcpPort                = 9000
      httpPort               = 8123
      username               = "default"
      password               = ""
      database               = "default"
      singleNode             = false
      clusterName            = "sentry-cluster"
      distributedClusterName = "sentry-cluster"
    }
  })
}
