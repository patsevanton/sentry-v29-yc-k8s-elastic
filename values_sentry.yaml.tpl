user:
  create: true
  email: "${user_email}"
  password: "${sentry_admin_password}"

images:
  sentry:
    repository: "${sentry_image_repository}"
    tag: "${sentry_image_tag}"
  snuba:
    repository: "${snuba_image_repository}"
    tag: "${snuba_image_tag}"

route:
  main:
    enabled: false

ingress:
  enabled: ${ingress_enabled}
  ingressClassName: "${ingress_class_name}"
  hostname: "${ingress_hostname}"

system:
  url: "${system_url}"

config:
  sentryConfPy: |
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

externalClickhouse:
  host: "${external_clickhouse.host}"
  tcpPort: ${external_clickhouse.tcpPort}
  secure: ${external_clickhouse.secure}
  httpPort: ${external_clickhouse.httpPort}
  username: "${external_clickhouse.username}"
  password: "${external_clickhouse.password}"
  database: "${external_clickhouse.database}"
  singleNode: ${external_clickhouse.singleNode}
  clusterName: "${external_clickhouse.clusterName}"
  distributedClusterName: "${external_clickhouse.distributedClusterName}"

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

# Used when kafka.enabled = false (external Kafka).
externalKafka:
%{ if length(external_kafka.cluster) > 0 ~}
  cluster:
%{ for broker in external_kafka.cluster ~}
    - host: "${broker.host}"
      port: ${broker.port}
%{ endfor ~}
%{ endif ~}
  sasl:
    mechanism: "${external_kafka.sasl.mechanism}"
    username: "${external_kafka.sasl.username}"
    password: "${external_kafka.sasl.password}"
  security:
    protocol: "${external_kafka.security.protocol}"
  provisioning:
    enabled: ${external_kafka.provisioning.enabled}
    replicationFactor: ${external_kafka.provisioning.replicationFactor}
    numPartitions: ${external_kafka.provisioning.numPartitions}

sentry:
  # Taskbroker does not inherit externalKafka.sasl/security automatically in this chart.
  # Explicit env vars are required for managed Kafka with SASL, otherwise taskbroker pods
  # connect as plaintext and fail with BrokerTransportFailure / SASL auth errors.
  taskBroker:
    env:
      - name: TASKBROKER_KAFKA_SECURITY_PROTOCOL
        value: "${external_kafka.security.protocol}"
      - name: TASKBROKER_KAFKA_SASL_MECHANISM
        value: "${external_kafka.sasl.mechanism}"
      - name: TASKBROKER_KAFKA_SASL_USERNAME
        value: "${external_kafka.sasl.username}"
      - name: TASKBROKER_KAFKA_SASL_PASSWORD
        value: "${external_kafka.sasl.password}"
      - name: TASKBROKER_KAFKA_DEADLETTER_CLUSTER
        value: "${join(",", [for broker in external_kafka.cluster : "${broker.host}:${broker.port}"])}"
      - name: TASKBROKER_KAFKA_DEADLETTER_TOPIC
        value: "taskworker-dlq"
      - name: TASKBROKER_KAFKA_DEADLETTER_SECURITY_PROTOCOL
        value: "${external_kafka.security.protocol}"
      - name: TASKBROKER_KAFKA_DEADLETTER_SASL_MECHANISM
        value: "${external_kafka.sasl.mechanism}"
      - name: TASKBROKER_KAFKA_DEADLETTER_SASL_USERNAME
        value: "${external_kafka.sasl.username}"
      - name: TASKBROKER_KAFKA_DEADLETTER_SASL_PASSWORD
        value: "${external_kafka.sasl.password}"

hooks:
  activeDeadlineSeconds: ${sentry_hooks_active_deadline_seconds}

%{ if enable_clickhouse_dns_search ~}
dnsPolicy: ClusterFirst
dnsConfig:
  searches:
    - sentry.svc.cluster.local
    - svc.cluster.local
    - cluster.local
    - ${clickhouse_dns_search_suffix}
%{ endif ~}

filestore:
  backend: s3
  s3:
    accessKey: "${filestore.s3.accessKey}"
    secretKey: "${filestore.s3.secretKey}"
    bucketName: "${filestore.s3.bucketName}"
    endpointUrl: "https://storage.yandexcloud.net"
    region_name: "ru-central1"
    signature_version: "s3v4"
    default_acl: "private"

symbolicator:
  enabled: true
  api:
    securityContext:
      fsGroup: 65532
    usedeployment: false
    persistence:
      enabled: true
      size: "1Gi"
