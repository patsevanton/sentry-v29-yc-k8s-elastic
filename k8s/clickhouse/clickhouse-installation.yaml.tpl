# ClickHouseInstallation CRD for Altinity clickhouse-operator.
# Перед применением установите оператор: см. README.md § 0.
# Шаблон генерируется Terraform (clickhouse.tf) → k8s/clickhouse/clickhouse-installation.yaml.
#
# Endpoint для Sentry (Snuba):
#   chi-sentry-clickhouse-sentry-clickhouse-0-0.clickhouse.svc.cluster.local:9000 (TCP)
#   chi-sentry-clickhouse-sentry-clickhouse-0-0.clickhouse.svc.cluster.local:8123 (HTTP)
#
# system.clusters.cluster = "sentry-clickhouse" (совпадает с cluster.name ниже).
# Порт в system.clusters — 9000 (native TCP, без TLS).
apiVersion: clickhouse.altinity.com/v1
kind: ClickHouseInstallation
metadata:
  name: sentry-clickhouse
  namespace: clickhouse
spec:
  configuration:
    # Автоматическое создание базы данных sentry при старте кластера.
    databases:
      sentry/name: sentry
    # Пользователь sentry: пароль задаётся через SHA256 hex (Terraform генерирует random_password).
    # access_management = 1 позволяет пользователю управлять объектами в БД.
    users:
      sentry/password_sha256_hex: "${clickhouse_sentry_password_sha256}"
      sentry/access_management: 1
      sentry/profile: default
    clusters:
      - name: sentry-clickhouse
        layout:
          shardsCount: 1
          replicasCount: 1
    settings:
      timezone: UTC
  templates:
    volumeClaimTemplates:
      - name: clickhouse-data
        spec:
          accessModes:
            - ReadWriteOnce
          storageClassName: yc-network-hdd
          resources:
            requests:
              storage: 20Gi
    podTemplates:
      - name: clickhouse-pod
        spec:
          containers:
            - name: clickhouse-server
              image: clickhouse/clickhouse-server:25.3
              resources:
                requests:
                  cpu: 500m
                  memory: 2Gi
                limits:
                  memory: 2Gi
              volumeMounts:
                - name: clickhouse-data
                  mountPath: /var/lib/clickhouse
              ports:
                - name: http
                  containerPort: 8123
                - name: tcp
                  containerPort: 9000
              readinessProbe:
                tcpSocket:
                  port: 9000
                initialDelaySeconds: 10
                periodSeconds: 5
                timeoutSeconds: 5
                failureThreshold: 12
