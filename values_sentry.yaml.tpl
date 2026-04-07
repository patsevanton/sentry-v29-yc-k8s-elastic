# Минимальный пример с nodestore в Elasticsearch (ECK).
# Кластер: elasticsearch.yaml, сервис HTTP — sentry-nodestore-es-http.elasticsearch.svc:9200.
# См. README.md § 1 и Dockerfile.sentry-nodestore.
#
# Этот файл — шаблон Terraform templatefile(). Не редактируйте values_sentry.yaml
# напрямую: он генерируется из этого .tpl. Правьте переменные в templatefile.tf.

# Пользовательская конфигурация для Sentry
user:
  create: true
  email: "${user_email}"
  password: "${sentry_admin_password}"

# Контейнерные образы компонентов Sentry
images:
  sentry:
    repository: "${sentry_image_repository}"
    tag: "${sentry_image_tag}"
  snuba:
    repository: "${snuba_image_repository}"
    tag: "${snuba_image_tag}"

# Доступ по sentry.apatsev.org.ru через ingress-nginx (стандартный Ingress).
# Включить ровно один способ маршрутизации: route.main, ingress или nginx.
route:
  main:
    enabled: false

ingress:
  enabled: ${ingress_enabled}
  ingressClassName: "${ingress_class_name}"
  hostname: "${ingress_hostname}"

# URL для CSRF и редиректов
system:
  url: "${system_url}"

# Nodestore: образ с sentry-nodestore-elastic (images.sentry выше). После первого деплоя:
# kubectl -n sentry exec -it deploy/sentry-web -- sentry upgrade --with-nodestore
config:
  sentryConfPy: |
    # НЕ делайте «from sentry.conf.server import *» здесь: этот блок дописывается в КОНЕЦ
    # сгенерированного sentry.conf.py, где SENTRY_CACHE уже задан чартом. Повторный import *
    # сбрасывает SENTRY_CACHE в None → ImproperlyConfigured: cache.backend.

    from elasticsearch import Elasticsearch

    es = Elasticsearch(
        ["${elasticsearch_url}"],
        request_timeout=60,
        max_retries=3,
        retry_on_timeout=True,
    )

    SENTRY_NODESTORE = "sentry_nodestore_elastic.ElasticNodeStorage"
    SENTRY_NODESTORE_OPTIONS = {
        "es": es,
        "refresh": False,
    }

    SENTRY_AIR_GAP = True

    INSTALLED_APPS = list(INSTALLED_APPS)
    INSTALLED_APPS.append("sentry_nodestore_elastic")
    INSTALLED_APPS = tuple(INSTALLED_APPS)

# Внешний ClickHouse (до helm install Sentry: README §2, иначе Job sentry-db-check
# зависнет с «getaddrinfo: Name does not resolve»).
externalClickhouse:
  host: "${external_clickhouse.host}"
  tcpPort: ${external_clickhouse.tcpPort}
  httpPort: ${external_clickhouse.httpPort}
  username: "${external_clickhouse.username}"
  password: "${external_clickhouse.password}"
  database: "${external_clickhouse.database}"
  singleNode: ${external_clickhouse.singleNode}

# В кластере: PostgreSQL, Redis, Kafka (Kraft — без Zookeeper)
postgresql:
  enabled: ${postgresql_enabled}
redis:
  enabled: ${redis_enabled}
kafka:
  enabled: ${kafka_enabled}
  zookeeper:
    enabled: false
  kraft:
    enabled: true
  provisioning:
    enabled: true
    replicationFactor: 1

# Локальный filestore: том на узле часто монтируется как root:root; без fsGroup пользователь
# sentry (uid/gid 999 в официальном образе) не может писать в /var/lib/sentry/files.
# Чарт подставляет sentry.web.securityContext в pod.spec.securityContext (см. deployment-sentry-web).
# При RWO и одном томе — Recreate, чтобы при обновлении не было двух подов с одним PVC.
sentry:
  web:
    strategyType: Recreate
    securityContext:
      fsGroup: 999

# Filestore: S3-совместимое хранилище (Yandex Object Storage) вместо локальной ФС.
# При filesystem-бэкенде PVC (RWO) доступен только web-поду; taskworker-ы при
# assemble debug-файлов не находят blob-ы → FileNotFoundError. S3 доступен всем подам.
# Временно отключено — проверка влияния на source maps (chart уйдёт на filesystem по умолчанию).
# filestore:
#   backend: s3
#   s3:
#     accessKey: "${filestore.s3.accessKey}"
#     secretKey: "${filestore.s3.secretKey}"
#     bucketName: "${filestore.s3.bucketName}"
#     endpointUrl: "https://storage.yandexcloud.net"
#     region_name: "ru-central1"
#     signature_version: "s3v4"
#     default_acl: "private"

# Symbolicator: скачивание и кеш debug-символов для native stack traces.
symbolicator:
  enabled: true
  api:
    securityContext:
      fsGroup: 65532
    usedeployment: false
    persistence:
      enabled: true
      size: "1Gi"
