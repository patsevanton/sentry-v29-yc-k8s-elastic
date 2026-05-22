# Развёртывание Sentry v31.3.1 в Yandex Cloud на Kubernetes

> **Важно:** для production-режима рекомендуется заменить встроенные PostgreSQL и Redis из Helm-чарта Sentry на **Yandex Managed PostgreSQL** и **Managed Redis (Valkey)**. Встроенные БД подходят только для dev/test окружений. В Terraform нужно создать ресурсы `yandex_mdb_postgresql_cluster` и `yandex_mdb_redis_cluster`, а в `values_sentry.yaml.tpl` указать `externalPostgresql` и `externalRedis` вместо `postgresql.enabled: true` и `redis.enabled: true`.

TODO проверить все ли файлы указаны в readme

## Цели статьи

Статья описывает процесс развёртывания Sentry v31.3.1 в Yandex Cloud на кластере Kubernetes. Будет развёрнуто:

- Инфраструктура через Terraform (K8S, Kafka, PostgreSQL, Object Storage, VPC).
- ClickHouse через [Altinity clickhouse-operator](https://github.com/Altinity/clickhouse-operator) в Kubernetes (кластер 1 shard × 3 replicas + ClickHouse Keeper).
- ~~Elasticsearch 9.x через ECK Operator для nodestore~~ (перенесено в `backup/`, не используется — nodestore настроен на стандартный бэкенд Sentry).
- Sentry в Kubernetes через Helm-чарт.
- S3 filestore (Yandex Object Storage) для артефактов Sentry (debug-символы, source maps).
- KEDA — автоскейлинг воркеров Sentry по накоплению сообщений в Kafka-очередях.
- VictoriaMetrics K8s Stack (VMSingle, VMAgent, Grafana, vmalert, node-exporter, kube-state-metrics).
- Мониторинг Sentry через Prometheus exporter.
- Мониторинг Yandex Managed Kafka в Grafana (VMStaticScrape + дашборд).
- Демо-клиенты Sentry (Python/FastAPI, Node.js/Express) и загрузка source maps.

## Применение через Terraform (корень репозитория)

Инфраструктура применяется одним root Terraform-стеком из корня репозитория (`*.tf` в root).

Подготовка:

```bash
export YC_TOKEN=$(yc iam create-token)
export YC_CLOUD_ID=$(yc config get cloud-id)
export YC_FOLDER_ID="<ваш-folder-id>"
```

Применение инфраструктуры:

```bash
terraform init
terraform apply
```

### 0. ClickHouse (Altinity clickhouse-operator)

ClickHouse для Sentry/Snuba развёрнут в Kubernetes через [Altinity clickhouse-operator](https://github.com/Altinity/clickhouse-operator). Кластер: **1 shard × 3 replicas**, namespace `clickhouse`. Координация репликации через **ClickHouse Keeper** (3 узла, тот же namespace).

**Преимущества перед Managed ClickHouse:**
- `system.clusters` отдаёт порт 9000 (no TLS) — Snuba работает без `secure=true`;
- DNS-хостнеймы резолвятся внутри кластера;
- Полный контроль над версией ClickHouse, конфигурацией и ресурсами;
- Clickhouse-operator обычно дешевле;

**0.1. Установка clickhouse-operator**

Operator устанавливается вручную. Helm-values задаются в файле [clickhouse-operator-values.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/clickhouse-operator-values.yaml) (operator смотрит только namespace `clickhouse`).

```bash
helm repo add clickhouse-operator https://helm.altinity.com
helm repo update
helm upgrade --install clickhouse-operator clickhouse-operator/altinity-clickhouse-operator \
  --version 0.27.0 \
  --namespace clickhouse-operator \
  --create-namespace \
  -f clickhouse-operator-values.yaml \
  --wait
```

Проверка:

```bash
kubectl -n clickhouse-operator get pods
kubectl get crd | grep clickhouse
```


**0.2. ClickHouse Keeper (координация репликации)**

ClickHouse с `replicasCount > 1` требует ZooKeeper-совместимый координатор для репликации данных. В этом проекте используется [ClickHouse Keeper](https://clickhouse.com/docs/guides/sre/keeper/clickhouse-keeper).

> **ВАЖНО:** Keeper **ДОЛЖЕН** быть запущен и готов **ДО** применения `ClickHouseInstallation`. Иначе ClickHouse не сможет подключиться к координатору, и Snuba-миграции завершатся ошибкой: `Cannot use any of provided ZooKeeper nodes`.

```bash
kubectl create namespace clickhouse
kubectl apply -f k8s/clickhouse/clickhouse-keeper-installation.yaml
```

Дождитесь готовности всех 3 подов Keeper:

```bash
kubectl -n clickhouse get pods -l clickhouse-keeper.altinity.com/chi=sentry-keeper
# Все поды должны быть в статусе Running 1/1
```

**0.3. Кластер ClickHouse**

```bash
kubectl apply -f k8s/clickhouse/clickhouse-installation.yaml
```

Проверка готовности:

```bash
kubectl -n clickhouse get clickhouseinstallation sentry-clickhouse
kubectl -n clickhouse get pods,svc
```

Убедитесь, что в STATUS отображается `Completed` и что поды Running.

**0.4. Endpoint для Sentry (Snuba)**

Кластер доступен из namespace `sentry` по адресу load-balancer сервиса:
- **TCP**: `clickhouse-sentry-clickhouse.clickhouse.svc.cluster.local:9000`
- **HTTP**: `clickhouse-sentry-clickhouse.clickhouse.svc.cluster.local:8123`

В `system.clusters` имя кластера — `sentry-cluster`, порт `9000`. Значения `clusterName` и `distributedClusterName` в `values_sentry.yaml` должны совпадать с этим именем.

Пользователь `default` используется без пароля (`networks/ip: 0.0.0.0/0`).

### 1. ~~Elasticsearch (nodestore) и оператор ECK~~ (не используется)

> **Статус:** компоненты перенесены в `backup/`. Nodestore работает на стандартном бэкенде Sentry (Bigtable/Redis). Историческая инструкция, манифесты и Dockerfile сохранены в `backup/elasticsearch-sections.md`, `backup/elasticsearch.yaml`, `backup/Dockerfile.sentry-nodestore`, `backup/Dockerfile.snuba-nodestore`.

### 2. Prometheus Operator CRD

VictoriaMetrics Operator по умолчанию включает конвертацию Prometheus-совместимых CRD (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`, `Probe`, `ScrapeConfig`, `AlertmanagerConfig` из `monitoring.coreos.com`). Если эти CRD не установлены в кластере, VictoriaMetrics operator падает при старте с ошибкой:

```
if kind is a CRD, it should be installed before calling Start
```

Установите **только CRD** (без самого Prometheus Operator):

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus-operator-crds prometheus-community/prometheus-operator-crds
```

Проверка:

```bash
kubectl get crd | grep monitoring.coreos.com
```

### 3. VictoriaMetrics K8s Stack

Стек [VictoriaMetrics K8s Stack](https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/) поднимает оператор VictoriaMetrics, **VMSingle**, **VMAgent**, **Grafana**, **vmalert**, Alertmanager, **node-exporter** и **kube-state-metrics**.

Нужен уже установленный **ingress-nginx** с классом `nginx` или Gateway API.

```bash
kubectl create namespace vmks
helm upgrade --install vmks oci://ghcr.io/victoriametrics/helm-charts/victoria-metrics-k8s-stack \
  --version 0.79.1 \
  -n vmks \
  -f vmks-values.yaml \
  --wait --timeout=15m
```

**Пароль Grafana.**

```bash
kubectl -n vmks get secret vmks-grafana -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

Логин по умолчанию — `**admin**` (его можно прочитать из ключа `admin-user` того же Secret).

Веб-интерфейс Grafana доступен по адресу **[http://grafana.apatsev.org.ru](http://grafana.apatsev.org.ru)**.

### 4. KEDA (автоскейлинг по Kafka lag)

Для автоскейлинга воркеров Sentry по накоплению сообщений в Kafka-очередях установите [KEDA](https://keda.sh/) в отдельный namespace.

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
kubectl create namespace keda
helm upgrade --install keda kedacore/keda \
  --version 2.19.0 \
  -n keda \
  --wait --timeout=10m
```

Проверка:

```bash
kubectl -n keda get pods
kubectl get crd | grep "keda.sh"
```

После установки можно добавлять `ScaledObject` для нужных deployment/statefulset (например, ingest-consumer-ов), с триггером Kafka lag.

### 4.1. Репозиторий Sentry

Подключите Helm-репозиторий чарта Sentry. Namespace `sentry` можно создать заранее или при установке в **§6** флагом `--create-namespace`.

```bash
kubectl create namespace sentry
helm repo add sentry https://sentry-kubernetes.github.io/charts
helm repo update
```

Если namespace уже есть, `kubectl create namespace sentry` завершится ошибкой — это нормально. Либо опустите эту строку и полагайтесь только на `--create-namespace` у Helm.

### 4.2. S3 filestore (Yandex Object Storage)

Для хранения артефактов (debug-символы, source maps, blob-ы загрузок) в `values_sentry.yaml` должен быть указан S3-бэкенд:

```yaml
filestore:
  backend: s3
```

По умолчанию чарт Sentry хранит артефакты на локальной ФС (`/var/lib/sentry/files`) с PVC в режиме **RWO** (ReadWriteOnce). RWO-том доступен только одному поду (обычно `sentry-web`); taskworker-ы при сборке (`assemble`) debug-файлов не находят blob-ы → `FileNotFoundError` / `internal server error` в UI. S3-бэкенд доступен всем подам одновременно и решает эту проблему.

### 4.3. Kafka credentials (Secret для внешнего Kafka)

Так как используем внешнюю Kafka (Yandex Managed Kafka), чарт Sentry ожидает Secret с credentials для SASL-аутентификации. В `values_sentry.yaml` задано `externalKafka.sasl.existingSecret: "kafka-credentials"` — этот Secret должен существовать в namespace `sentry` **до** запуска `helm upgrade --install sentry`, иначе Job `sentry-kafka-provisioning` завершится ошибкой `secret "kafka-credentials" not found`.

Ключи Secret соответствуют секции `externalKafka.sasl.existingSecretKeys` в values:
- `mechanism` — механизм SASL (например, `SCRAM-SHA-512`)
- `username` — имя пользователя Kafka
- `password` — пароль Kafka

Если credentials уже есть в Terraform outputs:

```bash
kubectl create namespace sentry
kafka_user=$(terraform output -raw managed_kafka_user)
kafka_password=$(terraform output -raw managed_kafka_password)
kubectl -n sentry create secret generic kafka-credentials \
  --from-literal=mechanism='SCRAM-SHA-512' \
  --from-literal=username="${kafka_user}" \
  --from-literal=password="${kafka_password}"
```

Если credentials задаются вручную, замените значения на реальные. При использовании встроенного Kafka (`kafka.enabled: true`) этот Secret не нужен.

### 5. Установка Sentry

**Порядок зависимостей.** Чарт поднимает PostgreSQL и Redis в namespace `sentry`, а **ClickHouse работает в k8s через clickhouse-operator** (namespace `clickhouse`, `externalClickhouse` в [values_sentry.yaml.tpl](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/values_sentry.yaml.tpl)). Kafka по умолчанию внешняя (Yandex Managed Kafka); встроенный Kafka включается переменной `sentry_incluster_kafka_enabled`. Сначала выполните **§0** (ClickHouse Operator + Keeper + ClickHouseInstallation), **§3–§4** (Prometheus CRD + VictoriaMetrics), **§5** (KEDA + репозиторий Helm), затем команду ниже.

Установка с `values_sentry.yaml` (генерируется из [values_sentry.yaml.tpl](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/values_sentry.yaml.tpl) через `terraform apply`): в файле заданы параметры ClickHouse из k8s-сервиса.

```bash
helm upgrade --install sentry sentry/sentry --version 31.3.1 -n sentry \
  -f values_sentry.yaml --timeout=7200s --create-namespace
```

**Устанавливается долго:** первый `helm upgrade --install` часто занимает 20–40 минут.

После установки зайдите в Sentry в браузере: **[http://sentry.apatsev.org.ru](http://sentry.apatsev.org.ru)** (DNS и ingress — **§9**; если задали другой хост в Ingress/`values`, используйте его).

**Relay** и **taskbroker** отдельно не настраиваются.


#### TODO проверить HPA taskworker-ingest


#### Автоскейлинг taskworker-ingest (KEDA ScaledObject)

После установки Sentry и KEDA примените манифест [k8s/keda-taskworker-ingest.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/keda-taskworker-ingest.yaml) — `ScaledObject` для `sentry-taskworker-ingest` с триггером Kafka lag:

```bash
kubectl apply -f k8s/keda-taskworker-ingest.yaml
```

- **minReplicaCount:** 1, **maxReplicaCount:** 8
- **Триггер:** `kafka_group_topic_partition_lag` (группа `taskworker-ingest`, топик `taskworker-ingest`) — запрос к VictoriaMetrics (§4)
- **threshold:** 1000 (порог масштабирования), **activationThreshold:** 100 (порог «пробуждения» из 0→1)
- **pollingInterval:** 30 сек, **cooldownPeriod:** 600 сек (10 мин)

Проверка:

```bash
kubectl -n sentry get scaledobject taskworker-ingest
```

### 6. Проверка подов и логов

В конце установки Sentry убедитесь, что все Job завершились (статус `Completed`). Пока Job ещё запущены, поды инициализации могут быть в статусе `Running`, а Helm может ждать готовности.

```bash
kubectl -n sentry get jobs
kubectl -n sentry get pods
```

Когда все нужные Job в `COMPLETIONS 1/1`, проверьте логи:

```bash
kubectl -n sentry logs deployment/sentry-snuba-api --tail=20
kubectl -n sentry logs sentry-taskbroker-ingest-0 --tail=20
kubectl -n sentry logs deployment/sentry-web --tail=20
```

### 7. Мониторинг Sentry (Prometheus exporter)

После установки Sentry (**§6**) и VictoriaMetrics K8s Stack (**§4**) поднимите [sentry-prometheus-exporter](https://github.com/italux/sentry-prometheus-exporter) ([манифест](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/sentry-prometheus-exporter.yaml)): метрики на порту **9790**, путь `/metrics/`.

> **Токен создаётся только вручную через UI Sentry** — автоматизировать создание API-токена невозможно, т.к. Sentry не предоставляет API для выпуска токенов внутренних интеграций.

1. Создайте токен в UI Sentry: **Settings → Developer Settings → Custom Integrations → Create New Integration** (тип **Internal Integration**). В **Permissions** задайте **Read** для Organization, Project, Issue & Event; для Release выберите **Admin** (только так токен получит `project:releases`). Скопируйте токен после сохранения. Подробнее: [Internal Integration](https://docs.sentry.io/product/integrations/integration-platform/internal-integration/), [как создать auth token](https://docs.sentry.io/api/guides/create-auth-token/).

2. Создайте Secret и примените манифесты:

```bash
kubectl -n sentry create secret generic sentry-auth-token --from-literal=token='<SENTRY_AUTH_TOKEN>'
kubectl apply -f k8s/sentry-prometheus-exporter.yaml
kubectl apply -f k8s/vmscrape-sentry-prometheus-exporter.yaml
```

3. Импортируйте дашборд [dashboard/sentry-issues-events-overview.json](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/dashboard/sentry-issues-events-overview.json) в Grafana (`Dashboards → New → Import`).

4. Проверьте, что exporter работает корректно:

```bash
# 1. Под Running, без рестартов
kubectl -n sentry get pods -l app=sentry-prometheus-exporter

# 2. Нет ошибок DNS в логах (должны быть "projects loaded from API: N")
kubectl -n sentry logs -l app=sentry-prometheus-exporter --tail=20

# 3. VMServiceScrape в статусе operational
kubectl -n vmks get vmservicescrape sentry-prometheus-exporter

# 4. Метрики доступны (запрос занимает до 60 сек — exporter опрашивает Sentry API)
kubectl -n sentry port-forward svc/sentry-prometheus-exporter 9790:9790 &
curl -s --max-time 90 http://localhost:9790/metrics/ | grep -E 'sentry_open_issue_events|sentry_events_total|sentry_issues_bucket'
kill %1

# 5. Метрики видны в VMSingle
curl -s "http://vmsingle.apatsev.org.ru/api/v1/query?query=sentry_open_issue_events" | python3 -m json.tool
```

### 7.1. Мониторинг Yandex Managed Kafka в Grafana

Для Managed Kafka в Yandex Cloud метрики берутся напрямую из Yandex Monitoring endpoint `https://monitoring.api.cloud.yandex.net/monitoring/v2/prometheusMetrics` c параметрами `folderId` и `service=managed-kafka` (официальный export в формате Prometheus).

Terraform автоматически создаёт сервисный аккаунт `monitoring-viewer-sa` с ролью `monitoring.viewer`, генерирует API-ключ и рендерит два манифеста:
- [k8s/vmstaticscrape-yc-managed-kafka.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/vmstaticscrape-yc-managed-kafka.yaml) — VMStaticScrape (из шаблона [.tpl](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/vmstaticscrape-yc-managed-kafka.yaml.tpl))
- [k8s/secret-yc-monitoring-api-key.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/secret-yc-monitoring-api-key.yaml) — K8S Secret с bearer-токеном (из шаблона [.tpl](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/secret-yc-monitoring-api-key.yaml.tpl))

Оба файла содержат секреты и добавлены в `.gitignore`. См. [monitoring.tf](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/monitoring.tf). Почему используется API-ключ вместо статического IAM-токена — см. [docs/yc-monitoring-auth.md](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/docs/yc-monitoring-auth.md).

1. Примените K8S Secret (содержит API-ключ, сгенерирован Terraform):

```bash
kubectl apply -f k8s/secret-yc-monitoring-api-key.yaml
```

2. Примените VMStaticScrape (содержит `folder_id`, сгенерирован Terraform):

```bash
kubectl apply -f k8s/vmstaticscrape-yc-managed-kafka.yaml
```

3. Проверьте, что vmagent видит target:

```bash
kubectl -n vmks get vmstaticscrape yc-managed-kafka
```

4. Импортируйте дашборд [dashboard/yc-managed-kafka-overview.json](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/dashboard/yc-managed-kafka-overview.json) в Grafana (`Dashboards -> New -> Import`) и выберите datasource Prometheus/VictoriaMetrics.

### 7.2. Мониторинг ClickHouse Operator в Grafana

После установки clickhouse-operator (**§0.1**) и VictoriaMetrics K8s Stack (**§4**) подключите scrape метрик operator'а.

Operator expose-ит Prometheus-метрики на порту **8888**. Манифест [k8s/vmscrape-clickhouse-operator.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/vmscrape-clickhouse-operator.yaml) создаёт `VMServiceScrape` в namespace `vmks` (где работает `VMAgent` из §4).

```bash
kubectl apply -f k8s/vmscrape-clickhouse-operator.yaml
```

Проверка:

```bash
kubectl -n vmks get vmservicescrape clickhouse-operator
```

Импортируйте дашборд ClickHouse Operator в Grafana (`Dashboards -> New -> Import`, загрузите JSON-файл, datasource — Prometheus/VictoriaMetrics). JSON-файл дашборда: [Altinity_ClickHouse_Operator_dashboard.json](https://github.com/Altinity/clickhouse-operator/blob/master/grafana-dashboard/Altinity_ClickHouse_Operator_dashboard.json) — показывает состояние оператора: количество CR, reconcile latency, количество managed ClickHouseInstallation.

### 8. Доступ к Sentry

Sentry доступен по адресу **[http://sentry.apatsev.org.ru](http://sentry.apatsev.org.ru)** через [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) (стандартный `Ingress`).

Убедитесь, что DNS-запись `sentry.apatsev.org.ru` указывает на внешний IP сервиса ingress-nginx (обычно `LoadBalancer` в namespace `ingress-nginx`):

```bash
kubectl -n ingress-nginx get svc
```

### 9. Демо-клиенты Sentry

Два HTTP-сервиса (Python / FastAPI и Node.js / Express) с одинаковыми маршрутами для проверки self-hosted Sentry: исключения, сообщения, транзакции, breadcrumbs, контекст.

> 📋 Полная сводка возможностей Sentry v31 и их реализации в проекте — в [docs/sentry-capabilities.md](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/docs/sentry-capabilities.md). Там же — рекомендуемый порядок внедрения новых фич.

#### Маршруты


| Путь                          | Описание                                                        |
| ----------------------------- | --------------------------------------------------------------- |
| `GET /health`                 | Проверка готовности (без DSN)                                   |
| `GET /demo/exception`         | Необработанное исключение                                       |
| `GET /demo/capture-exception` | Необработанное исключение (другой текст, как `/demo/exception`) |
| `GET /demo/message`           | `capture_message` (info + warning)                              |
| `GET /demo/transaction`       | Spans / performance                                             |
| `GET /demo/breadcrumb`        | Breadcrumb, затем ошибка                                        |
| `GET /demo/context`           | Теги, user, context + message                                   |


Без `SENTRY_DSN` маршруты `/demo/*` отвечают **503**; `/health` всегда **200**.

#### DSN

1. В UI Sentry создайте проекты (часто отдельно для Node и для Python) и скопируйте DSN для каждого. В Kubernetes — два Secret (`sentry-dsn-node`, `sentry-dsn-python`); значения могут отличаться или совпадать, если используете один и тот же проект Sentry для обоих SDK.
2. Скопируйте DSN каждого проекта (**Settings → Client Keys**). Для подов в кластере DSN должен указывать на **доступный из кластера** хост Sentry (часто тот же URL, что в браузере, или внутренний Ingress). Если события не доходят, проверьте DNS и сетевую связность до Relay/Ingress.

#### Запуск в Kubernetes

Зайти в Sentry UI и создать 2 проекта: Node и Python. После чего из корня репозитория запустить:

```bash
# Namespaces
kubectl apply -f demo/demo-python/namespace.yaml
kubectl apply -f demo/demo-nodejs/namespace.yaml

# DSN (по одному Secret на Python и Node):
kubectl create secret generic sentry-dsn-python -n demo-python \
  --from-literal=dsn='http://YOUR_SENTRY_DSN_PYTHON@sentry.apatsev.org.ru/PROJECT_ID'
kubectl create secret generic sentry-dsn-node -n demo-node \
  --from-literal=dsn='http://YOUR_SENTRY_DSN_NODE@sentry.apatsev.org.ru/PROJECT_ID'
# либо подставить dsn в secret-sentry-dsn-*.yaml и:
# kubectl apply -f demo/demo-python/secret-sentry-dsn-python.yaml -f demo/demo-nodejs/secret-sentry-dsn-node.yaml

# Deployments и Services
kubectl apply -f demo/demo-python/deployment-python.yaml
kubectl apply -f demo/demo-nodejs/deployment-node.yaml
kubectl apply -f demo/demo-python/service.yaml
```

Манифесты Secret с плейсхолдерами: [demo/demo-nodejs/secret-sentry-dsn-node.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/demo/demo-nodejs/secret-sentry-dsn-node.yaml), [demo/demo-python/secret-sentry-dsn-python.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/demo/demo-python/secret-sentry-dsn-python.yaml).

Переменная `DEMO_AUTO_EXCEPTION_INTERVAL_SEC` в манифестах demo (и при локальном запуске) задаёт интервал автоматической отправки исключений в Sentry; `0` отключает. Откройте проект в Sentry и убедитесь, что появились issues и (при включённом performance) транзакции.

### 10. Chaos Mesh (Fault Injection для тестирования устойчивости)

[Chaos Mesh](https://chaos-mesh.org/) — платформа для fault injection в Kubernetes, позволяет тестировать устойчивость Sentry к сбоям: убивать поды, задерживать/терять сетевые пакеты, нагружать CPU/内存, сбои дисков и т.д.

**Установка:**

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update
kubectl create namespace chaos-mesh
helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --version 2.8.2 \
  -n chaos-mesh \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set dashboard.securityMode=false \
  --wait --timeout=10m
```

Проверка:

```bash
kubectl -n chaos-mesh get pods
```

**Портал Chaos Mesh (Dashboard):**

```bash
kubectl -n chaos-mesh port-forward svc/chaos-dashboard 2333:2333 &
# Откройте http://localhost:2333
```

**Примеры экспериментов:**

- [k8s/chaos/kill-sentry-web.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/chaos/kill-sentry-web.yaml) — убийство пода `sentry-web` каждые 5 минут (`PodChaos`)
- [k8s/chaos/delay-clickhouse.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/chaos/delay-clickhouse.yaml) — задержка сети 200ms до ClickHouse на 5 минут (`NetworkChaos`)

Применение:

```bash
kubectl apply -f k8s/chaos/kill-sentry-web.yaml
kubectl apply -f k8s/chaos/delay-clickhouse.yaml
```

Остановка эксперимента:

```bash
kubectl -n chaos-mesh delete podchaos kill-sentry-web
kubectl -n chaos-mesh delete networkchaos delay-clickhouse
```

