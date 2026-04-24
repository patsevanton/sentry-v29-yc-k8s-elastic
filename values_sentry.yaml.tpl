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
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi

relay:
  init:
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  resources:
    requests:
      cpu: 200m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 4Gi

vroom:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi

uptimeChecker:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi

metrics:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi

pgbouncer:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi

sentry:
  # Taskbroker does not inherit externalKafka.sasl/security automatically in this chart.
  # Explicit env vars are required for managed Kafka with SASL, otherwise taskbroker pods
  # connect as plaintext and fail with BrokerTransportFailure / SASL auth errors.
  taskBroker:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
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
  web:
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi
  taskWorker:
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi
  taskScheduler:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  billingMetricsConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  genericMetricsConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  ingestConsumerAttachments:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  ingestConsumerEvents:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  ingestConsumerTransactions:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  ingestFeedback:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  ingestMonitors:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  ingestOccurrences:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  ingestProfiles:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  ingestReplayRecordings:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  metricsConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  monitorsClockTasks:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  monitorsClockTick:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  postProcessForwardErrors:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  postProcessForwardIssuePlatform:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  postProcessForwardTransactions:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  processSegments:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  processSpans:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerEvents:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerGenericMetrics:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerMetrics:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerResultsEapItems:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerTransactions:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  uptimeResults:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi

snuba:
  api:
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi
  cleanup:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  consumer:
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 2Gi
  eapItemsConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  genericMetricsCountersConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  genericMetricsDistributionConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  genericMetricsGaugesConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  genericMetricsSetsConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  groupAttributesConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  issueOccurrenceConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  metricsConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  outcomesBillingConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  outcomesConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  profilingChunksConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  profilingFunctionsConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  profilingProfilesConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  replacer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  replaysConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerEapItems:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerEvents:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerGenericMetricsCounters:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerGenericMetricsDistributions:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerGenericMetricsGauges:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerGenericMetricsSets:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerMetrics:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  subscriptionConsumerTransactions:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
  transactionsConsumer:
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi

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
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
    securityContext:
      fsGroup: 65532
    usedeployment: false
    persistence:
      enabled: true
      size: "1Gi"
