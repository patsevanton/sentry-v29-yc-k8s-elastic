# Развёртывание Sentry v31.0.0 в Yandex Cloud на Kubernetes

## Цели статьи

Статья описывает процесс развёртывания Sentry v31.0.0 в Yandex Cloud на кластере Kubernetes. Будет развёрнуто:

- Инфраструктура через Terraform (K8S, Kafka, PostgreSQL, Object Storage, VPC).
- ClickHouse через [Altinity clickhouse-operator](https://github.com/Altinity/clickhouse-operator) в Kubernetes (кластер 1 shard × 1 replica).
- ~~Elasticsearch 9.x через ECK Operator для nodestore~~ (перенесено в `backup/`, не используется — nodestore настроен на стандартный бэкенд Sentry).
- Sentry в Kubernetes через Helm-чарт.
- S3 filestore (Yandex Object Storage) для артефактов Sentry (debug-символы, source maps).
- KEDA — автоскейлинг воркеров Sentry по накоплению сообщений в Kafka-очередях.
- VictoriaMetrics K8s Stack (VMSingle, VMAgent, Grafana, vmalert, node-exporter, kube-state-metrics).
- Мониторинг Sentry через Prometheus exporter.
- Мониторинг Yandex Managed Kafka в Grafana (VMStaticScrape + дашборд).
- NodeLocal DNSCache (опционально) для снижения DNS-задержек.
- Демо-клиенты Sentry (Python/FastAPI, Node.js/Express, нативный C) и загрузка source maps.

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

ClickHouse для Sentry/Snuba развёрнут в Kubernetes через [Altinity clickhouse-operator](https://github.com/Altinity/clickhouse-operator). Кластер: **1 shard × 1 replica**, namespace `clickhouse`. Это заменяет Yandex Managed ClickHouse и решает проблему с TLS: `system.clusters` отдаёт порт **9000** (native TCP, без TLS), что позволяет Snuba работать без TLS-костылей.

**Преимущества перед Managed ClickHouse:**
- `system.clusters` отдаёт порт 9000 (no TLS) — Snuba работает без `secure=true`;
- DNS-хостнеймы резолвятся внутри кластера без `dnsConfig.searches`;
- Полный контроль над версией ClickHouse, конфигурацией и ресурсами.

**0.1. Установка clickhouse-operator**

Operator устанавливается вручную. Helm-values задаются в файле [clickhouse-operator-values.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/clickhouse-operator-values.yaml) (operator смотрит только namespace `clickhouse`).

```bash
helm repo add clickhouse-operator https://helm.altinity.com
helm repo update
helm upgrade --install clickhouse-operator clickhouse-operator/altinity-clickhouse-operator \
  --version 0.26.0 \
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

> **Известная проблема ([Altinity/clickhouse-operator#1930](https://github.com/Altinity/clickhouse-operator/issues/1930)):** если `ClickHouseOperatorConfiguration` применяется **после** запуска operator'а (например, вы изменили watched namespaces через values), operator не подхватывает изменение динамически. `ClickHouseInstallation` в новом namespace будет игнорироваться до рестарта пода operator'а. **Workaround:** после применения новой конфигурации выполните:
>
> ```bash
> kubectl rollout restart deployment -n clickhouse-operator
> ```
>
> При установке через Helm-values (как в этом проекте) проблема не возникает — namespace задаётся до первого запуска.

**0.2. Кластер ClickHouse**

Манифест CRD — [k8s/clickhouse/clickhouse-installation.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/clickhouse/clickhouse-installation.yaml). Operator не имеет встроенной декларативной поддержки `databases` в CRD (`spec.configuration.databases` не существует). База данных `sentry` создаётся через init-скрипт, смонтированный в `/docker-entrypoint-initdb.d` (официальный паттерн Altinity — [02-templates-05-bootstrap-schema.yaml](https://github.com/Altinity/clickhouse-operator/blob/master/docs/chi-examples/02-templates-05-bootstrap-schema.yaml)). Скрипт хранится в ConfigMap `clickhouse-initdb` и выполняется при первом запуске пода (env `CLICKHOUSE_ALWAYS_RUN_INITDB_SCRIPTS=true`). Повторные запуски не пересоздают существующую БД (`CREATE DATABASE IF NOT EXISTS`).

```bash
kubectl create namespace clickhouse
kubectl apply -f k8s/clickhouse/clickhouse-installation.yaml
```

Проверка готовности:

```bash
kubectl -n clickhouse get clickhouseinstallation sentry-clickhouse
kubectl -n clickhouse get pods,svc
```

Убедитесь, что в STATUS отображается `Completed` и что под Running:

```bash
kubectl -n clickhouse exec -it chi-sentry-clickhouse-single-node-0-0-0 -- \
  clickhouse-client -q "SHOW DATABASES"
```

В списке должна быть база `sentry`.

**0.3. Endpoint для Sentry (Snuba)**

Кластер доступен из namespace `sentry` по адресам:
- **TCP**: `chi-sentry-clickhouse-single-node-0-0.clickhouse.svc.cluster.local:9000`
- **HTTP**: `chi-sentry-clickhouse-single-node-0-0.clickhouse.svc.cluster.local:8123`

В `system.clusters` имя кластера — `single-node`, порт `9000`. Значения `clusterName` и `distributedClusterName` в `values_sentry.yaml` должны совпадать с этим именем.

Пользователь `default` используется без пароля (`networks/ip: 0.0.0.0/0`). База данных `sentry` создаётся init-скриптом из ConfigMap при первом запуске.

### 1. NodeLocal DNSCache (опционально)

[NodeLocal DNSCache](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/) — кэш DNS на каждом узле (DaemonSet в `kube-system`), снижает задержки и нагрузку на CoreDNS. В манифесте [k8s/nodelocaldns.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/nodelocaldns.yaml) в блоке `.:53` плейсхолдер `**__SENTRY_INGRESS_IP__**` нужно заменить на текущий внешний IP из `terraform output -raw ingress_public_ip` (тот же адрес, что резервирует [ip-dns.tf](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/ip-dns.tf) и куда указывают A-записи), чтобы поды резолвили тот же адрес, что и публичный DNS, даже если внешний DNS из кластера недоступен.

**Установка** (опционально). Нужен настроенный `kubectl` на кластер. Подставляется ClusterIP сервиса кластерного DNS (`kube-dns`), затем манифест применяется через `kubectl apply -f -`. Режим **iptables** у kube-proxy — типичный случай.

```bash
repo_root=$(git rev-parse --show-toplevel)
kubedns=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}')
domain=cluster.local
localdns=169.254.20.10
ingress_ip=$(terraform -chdir="${repo_root}" output -raw ingress_public_ip)
sed -e "s/__PILLAR__LOCAL__DNS__/${localdns}/g" \
    -e "s/__PILLAR__DNS__DOMAIN__/${domain}/g" \
    -e "s/__PILLAR__DNS__SERVER__/${kubedns}/g" \
    -e "s/__SENTRY_INGRESS_IP__/${ingress_ip}/g" \
    "${repo_root}/k8s/nodelocaldns.yaml" | kubectl apply -f -
```

Если kube-proxy в режиме **IPVS**, используйте подстановку из [документации](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/) (в т.ч. удаление `,__PILLAR__DNS__SERVER__` из `bind` и замена `__PILLAR__CLUSTER__DNS__`); для IPVS обычно меняют `--cluster-dns` у kubelet на адрес NodeLocal (`169.254.20.10`).

Проверка из пода:

```bash
kubectl run -it --rm dns-test --image=busybox:1.36 --restart=Never -- nslookup sentry.apatsev.org.ru
# ожидается IP из: terraform output -raw ingress_public_ip
```

### 2. ~~Elasticsearch (nodestore) и оператор ECK~~ (не используется)

> **Статус:** компоненты перенесены в `backup/`. Nodestore работает на стандартном бэкенде Sentry (Bigtable/Redis). Историческая инструкция, манифесты и Dockerfile сохранены в `backup/elasticsearch-sections.md`, `backup/elasticsearch.yaml`, `backup/Dockerfile.sentry-nodestore`, `backup/Dockerfile.snuba-nodestore`.

### 3. KEDA (автоскейлинг по Kafka lag)

Для автоскейлинга воркеров Sentry по накоплению сообщений в Kafka-очередях установите [KEDA](https://keda.sh/) в отдельный namespace.

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
kubectl create namespace keda
helm upgrade --install keda kedacore/keda \
  --version 2.16.1 \
  -n keda \
  --wait --timeout=10m
```

Проверка:

```bash
kubectl -n keda get pods
kubectl get crd | rg "keda.sh"
```

После установки можно добавлять `ScaledObject` для нужных deployment/statefulset (например, ingest-consumer-ов), с триггером Kafka lag.

### 3.1. Репозиторий Sentry

Подключите Helm-репозиторий чарта Sentry. Namespace `sentry` можно создать заранее или при установке в **§4** флагом `--create-namespace`.

```bash
kubectl create namespace sentry
helm repo add sentry https://sentry-kubernetes.github.io/charts
helm repo update
```

Если namespace уже есть, `kubectl create namespace sentry` завершится ошибкой — это нормально. Либо опустите эту строку и полагайтесь только на `--create-namespace` у Helm.

### 3.2. S3 filestore (Yandex Object Storage)

Для хранения артефактов (debug-символы, source maps, blob-ы загрузок) в `values_sentry.yaml` должен быть указан S3-бэкенд:

```yaml
filestore:
  backend: s3
```

По умолчанию чарт Sentry хранит артефакты на локальной ФС (`/var/lib/sentry/files`) с PVC в режиме **RWO** (ReadWriteOnce). RWO-том доступен только одному поду (обычно `sentry-web`); taskworker-ы при сборке (`assemble`) debug-файлов не находят blob-ы → `FileNotFoundError` / `internal server error` в UI. S3-бэкенд доступен всем подам одновременно и решает эту проблему.

### 4. Установка Sentry

**Порядок зависимостей.** Чарт поднимает PostgreSQL, Redis и Kafka в namespace `sentry`, а **ClickHouse работает в k8s через clickhouse-operator** (namespace `clickhouse`, `externalClickhouse` в [values_sentry.yaml.tpl](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/values_sentry.yaml.tpl)). Сначала выполните **§0** (ClickHouse Operator + CRD), **§3** (репозиторий Helm), затем команду ниже.

Установка с `values_sentry.yaml` (генерируется из [values_sentry.yaml.tpl](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/values_sentry.yaml.tpl) через `terraform apply`): в файле заданы параметры ClickHouse из k8s-сервиса.

```bash
helm upgrade --install sentry sentry/sentry --version 31.0.0 -n sentry \
  -f values_sentry.yaml --timeout=7200s --create-namespace
```

**Устанавливается долго:** первый `helm upgrade --install` часто занимает 20–40 минут и более — последовательно выполняются Job’ы (проверка/инициализация БД, provisioning Kafka, Snuba и миграции). Увеличенный timeout (`7200s` = 1 час) позволяет избежать прерывания установки при длительном выполнении Job. Смотрите `kubectl -n sentry get jobs` и логи подов Job при зависаниях. Пример строк (реальный прогон; в k9s колонка **AGE** часто отсортирована по возрастанию — значок **↑**):

| NAMESPACE | NAME | COMPLETIONS | DURATION | AGE |
|-----------|------|-------------|----------|-----|
| sentry | sentry-user-create | 1/1 | 14s | 18s |
| sentry | sentry-db-init | 1/1 | 2m2s | 2m21s |
| sentry | sentry-snuba-db-init | 1/1 | 6s | 16m |
| sentry | sentry-snuba-migrate | 1/1 | 13m | 16m |
| sentry | sentry-kafka-provisioning | 1/1 | 10m | 26m |
| sentry | sentry-db-check | 1/1 | 2m50s | 29m |

После установки зайдите в Sentry в браузере: **[http://sentry.apatsev.org.ru](http://sentry.apatsev.org.ru)** (DNS и ingress — **§8**; если задали другой хост в Ingress/`values`, используйте его).

**Relay** и **taskbroker** отдельно не настраиваются.

### 5. Проверка подов и логов

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

### 6. VictoriaMetrics K8s Stack

Стек [VictoriaMetrics K8s Stack](https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/) поднимает оператор VictoriaMetrics, **VMSingle**, **VMAgent**, **Grafana**, **vmalert**, Alertmanager, **node-exporter** и **kube-state-metrics**. Готовые значения — [vmks-values.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/vmks-values.yaml) (Ingress для UI хранилища и Grafana).

Нужен уже установленный **ingress-nginx** с классом `nginx` (в этом репозитории — Helm-релиз в [k8s.tf](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s.tf)).

```bash
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update
kubectl create namespace vmks
helm upgrade --install vmks vm/victoria-metrics-k8s-stack \
  --version 0.72.6 \
  -n vmks \
  -f vmks-values.yaml \
  --wait --timeout=15m
```

**Пароль Grafana.** Подчарт Grafana создаёт Secret с учётными данными администратора: имя вида `**<имя Helm-релиза>-grafana`**. Для команды выше (релиз `vmks`, namespace `vmks`) это `**vmks-grafana**`. Пароль:

```bash
kubectl -n vmks get secret vmks-grafana -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

Логин по умолчанию — `**admin**` (его можно прочитать из ключа `admin-user` того же Secret). Если вы установили стек под другим именем релиза, замените `vmks-grafana` на `<ваш-релиз>-grafana`.

Для имён из `vmks-values.yaml` (`vmsingle.apatsev.org.ru`, `grafana.apatsev.org.ru`) добавьте **A-записи** на тот же внешний IP, что у ingress (см. [ip-dns.tf](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/ip-dns.tf) для `sentry.apatsev.org.ru`).

Веб-интерфейс Grafana доступен по адресу **[http://grafana.apatsev.org.ru](http://grafana.apatsev.org.ru)**.

Интеграция с экспортёром Sentry — шаг 4 в **§7** и манифест [k8s/vmscrape-sentry-prometheus-exporter.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/vmscrape-sentry-prometheus-exporter.yaml).

### 7. Мониторинг Sentry (Prometheus exporter)

После установки Sentry (**§4**, namespace `sentry`) и VictoriaMetrics K8s Stack (**§6**) можно поднять [sentry-prometheus-exporter](https://github.com/italux/sentry-prometheus-exporter) манифестом [k8s/sentry-prometheus-exporter.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/sentry-prometheus-exporter.yaml): метрики на порту **9790**, путь `/metrics` (часто с редиректом на `/metrics/`). Внутри кластера API Sentry задаётся как `http://sentry-web.sentry.svc.cluster.local:9000/api/0/`. Переменная окружения `SENTRY_EXPORTER_ORG` должна быть равна **slug** организации — короткому идентификатору в URL (`/organizations/<slug>/`, тот же сегмент, что в запросах API `.../organizations/<slug>/`). Это не обязательно совпадает с **отображаемым именем** организации. В манифесте по умолчанию задано `sentry`: такой slug обычно у первой организации после мастера self-hosted Sentry; если в инстансе другая организация или slug — замените значение перед `kubectl apply`.

1. Создайте токен через [Internal Integration](https://docs.sentry.io/product/integrations/integration-platform/internal-integration/). В UI Sentry 26+: **Settings** → **Developer Settings** → **Custom Integrations** → **Create New Integration** → тип **Internal Integration** → **Next** → имя, например **`vm-sentry-prometheus-exporter`**. В **Permissions** для [sentry-prometheus-exporter](https://github.com/italux/sentry-prometheus-exporter) нужны scope API: **Organization** (`org:read`), **Project** (`project:read`), **Release** (`project:releases`), **Issue & Event** (`event:read`) ([описание scope](https://docs.sentry.io/api/permissions/)). Для **Organization**, **Project** и **Issue & Event** в выпадающих списках задайте **Read**. Для **Release** в Sentry 26+ в списке часто только **No Access** и **Admin** — отдельного **Read** нет: в API один scope `project:releases` на все операции с релизами (в т.ч. только чтение), поэтому выберите **Admin**, чтобы токен получил `project:releases` (это не «полный админ» организации, а уровень категории в форме интеграции). Остальные категории (**Team**, **Distribution**, **Member**, **Alerts** и т.д.) — **No Access**, если не нужны. Полный набор как в upstream; при отключённых метриках по событиям/релизам иногда хватает меньше scope. **Save** → скопируйте **Token** внизу страницы (до 20 токенов на интеграцию). См. [как создать auth token](https://docs.sentry.io/api/guides/create-auth-token/) и [документацию API](https://docs.sentry.io/api/auth/).
2. Сохраните токен в Secret в том же namespace, что и релиз Helm:

```bash
kubectl -n sentry create secret generic sentry-auth-token \
  --from-literal=token='<SENTRY_AUTH_TOKEN>'
```

3. Примените манифест:

```bash
kubectl apply -f k8s/sentry-prometheus-exporter.yaml
```

4. Подключите scrape через `VMServiceScrape`: [k8s/vmscrape-sentry-prometheus-exporter.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/vmscrape-sentry-prometheus-exporter.yaml) (`kubectl apply -f k8s/vmscrape-sentry-prometheus-exporter.yaml`). Манифест создаёт ресурс в namespace **`vmks`** (где работает `VMAgent` из §6) и указывает на Service в **`sentry`**; если положить `VMServiceScrape` только в `sentry`, vmagent его не подхватит. В нём же заданы `scrape_interval` / `scrapeTimeout` побольше: экспортёр отвечает медленно (запросы к API Sentry), иначе цель в vmagent будет **down** по таймауту. Либо укажите цель вручную, например `http://sentry-prometheus-exporter.sentry.svc.cluster.local:9790/metrics/`.

5. Импортируйте дашборд [dashboard/sentry-issues-events-overview.json](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/dashboard/sentry-issues-events-overview.json) в Grafana (`Dashboards -> New -> Import`) и выберите datasource Prometheus/VictoriaMetrics.

### 7.1. Мониторинг Yandex Managed Kafka в Grafana

Для Managed Kafka в Yandex Cloud метрики берутся напрямую из Yandex Monitoring endpoint `https://monitoring.api.cloud.yandex.net/monitoring/v2/prometheusMetrics` c параметрами `folderId` и `service=managed-kafka` (официальный export в формате Prometheus).

Terraform автоматически создаёт сервисный аккаунт `monitoring-viewer-sa` с ролью `monitoring.viewer`, генерирует API-ключ и рендерит манифест [k8s/vmstaticscrape-yc-managed-kafka.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/vmstaticscrape-yc-managed-kafka.yaml) из шаблона [k8s/vmstaticscrape-yc-managed-kafka.yaml.tpl](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/vmstaticscrape-yc-managed-kafka.yaml.tpl) с подставленным `folder_id` (см. [monitoring.tf](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/monitoring.tf)). Почему используется авторизованный ключ вместо статического IAM-токена — см. [docs/yc-monitoring-auth.md](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/docs/yc-monitoring-auth.md).

1. Получите значение API-ключа из Terraform output:

```bash
export MONITORING_API_KEY=$(terraform output -raw monitoring_api_key)
```

2. Создайте Kubernetes Secret в namespace `vmks`:

```bash
kubectl -n vmks create secret generic yc-monitoring-api-key \
  --from-literal=bearer="$MONITORING_API_KEY"
```

3. Примените манифест (он уже содержит `folder_id` после `terraform apply`):

```bash
kubectl apply -f k8s/vmstaticscrape-yc-managed-kafka.yaml
```

4. Проверьте, что vmagent видит target:

```bash
kubectl -n vmks get vmstaticscrape yc-managed-kafka
```

5. Импортируйте дашборд [dashboard/yc-managed-kafka-overview.json](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/dashboard/yc-managed-kafka-overview.json) в Grafana (`Dashboards -> New -> Import`) и выберите datasource Prometheus/VictoriaMetrics.

### 7.2. Мониторинг ClickHouse Operator в Grafana

После установки clickhouse-operator (**§0.1**) и VictoriaMetrics K8s Stack (**§6**) подключите scrape метрик operator'а.

Operator expose-ит Prometheus-метрики на порту **8888**. Манифест [k8s/vmscrape-clickhouse-operator.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/k8s/vmscrape-clickhouse-operator.yaml) создаёт `VMServiceScrape` в namespace `vmks` (где работает `VMAgent` из §6).

```bash
kubectl apply -f k8s/vmscrape-clickhouse-operator.yaml
```

Проверка:

```bash
kubectl -n vmks get vmscrape clickhouse-operator
```

### 8. Доступ к Sentry

Sentry доступен по адресу **[http://sentry.apatsev.org.ru](http://sentry.apatsev.org.ru)** через [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) (стандартный `Ingress`).

Убедитесь, что DNS-запись `sentry.apatsev.org.ru` указывает на внешний IP сервиса ingress-nginx (обычно `LoadBalancer` в namespace `ingress-nginx`):

```bash
kubectl -n ingress-nginx get svc
```

### 9. Демо-клиенты Sentry

Два HTTP-сервиса (Python / FastAPI и Node.js / Express) с одинаковыми маршрутами для проверки self-hosted Sentry: исключения, сообщения, транзакции, breadcrumbs, контекст.

> 📋 Полная сводка возможностей Sentry v30 и их реализации в проекте — в [docs/sentry-capabilities.md](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/docs/sentry-capabilities.md). Там же — рекомендуемый порядок внедрения новых фич.

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

Из корня репозитория:

```bash
kubectl apply -f demo/k8s/namespace.yaml
# DSN (по одному Secret на Node и Python):
kubectl create secret generic sentry-dsn-node -n demo-sentry \
  --from-literal=dsn='http://9be9665915921f2a8b66c9b7a3fddfc2@sentry.apatsev.org.ru/2'
kubectl create secret generic sentry-dsn-python -n demo-sentry \
  --from-literal=dsn='http://29697ef376aa88f040b8531a1941f830@sentry.apatsev.org.ru/3'
# либо подставить dsn в demo/k8s/secret-sentry-dsn-*.yaml и:
# kubectl apply -f demo/k8s/secret-sentry-dsn-node.yaml -f demo/k8s/secret-sentry-dsn-python.yaml

kubectl apply -f demo/k8s/deployment-python.yaml
kubectl apply -f demo/k8s/deployment-node.yaml
kubectl apply -f demo/k8s/service.yaml
```

Манифесты Secret с плейсхолдерами: `[demo/k8s/secret-sentry-dsn-node.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/demo/k8s/secret-sentry-dsn-node.yaml)`, `[demo/k8s/secret-sentry-dsn-python.yaml](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/demo/k8s/secret-sentry-dsn-python.yaml)`.

Переменная `DEMO_AUTO_EXCEPTION_INTERVAL_SEC` в манифестах demo (и при локальном запуске) задаёт интервал автоматической отправки исключений в Sentry; `0` отключает. Откройте проект в Sentry и убедитесь, что появились issues и (при включённом performance) транзакции.

#### Нативный пример (C, Linux ELF)

В [examples/sentry-native-debug-sample](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/examples/sentry-native-debug-sample) — минимальный `main.c` и скрипт [upload-releases.sh](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/examples/sentry-native-debug-sample/upload-releases.sh): сборка отладочного бинарника (`cc -g -O0`), создание имён релизов в Sentry и загрузка **debug information files** через `sentry-cli debug-files upload` (тип `elf`). Нужны установленные `**sentry-cli`** и компилятор `**cc**`.

Если при запуске получаете `sentry-cli: command not found`, установите CLI:

```bash
# Linux (x86_64): установка бинарника из GitHub Releases
curl -fL https://github.com/getsentry/sentry-cli/releases/latest/download/sentry-cli-Linux-x86_64 \
  -o sentry-cli
chmod +x sentry-cli
sudo mv sentry-cli /usr/local/bin/sentry-cli

# проверка
sentry-cli --version
```

Альтернатива через Node.js/npm:

```bash
npm install -g @sentry/cli
sentry-cli --version
```

Перед запуском задайте URL self-hosted (если не дефолтный `sentry.io`), организацию, проект и токен с правами на загрузку артефактов / релизов (см. комментарии в скрипте).

Как получить значения для `export` (подходит и для `examples/sentry-native-debug-sample`, и для `examples/sourcemap-upload`):

1. `SENTRY_ORG` — slug организации из URL в Sentry, например `https://sentry.example.com/organizations/<org-slug>/`.
2. `SENTRY_PROJECT` — slug проекта в **Project Settings → General Settings → Project Slug**.
3. `SENTRY_AUTH_TOKEN` — создайте токен через [Internal Integration](https://docs.sentry.io/product/integrations/integration-platform/internal-integration/) (как в **§7, шаг 1**): **Settings** → **Developer Settings** → **Custom Integrations** → **Create New Integration** → **Internal Integration**. Для скриптов upload обычно достаточно `project:releases` и `org:read` (при необходимости добавьте `project:read`).
4. Скопируйте значения в shell:

```bash
export SENTRY_URL="http://sentry.apatsev.org.ru"   # при необходимости
export SENTRY_AUTH_TOKEN="<SENTRY_AUTH_TOKEN>"
export SENTRY_ORG="sentry"
export SENTRY_PROJECT="native"

bash examples/sentry-native-debug-sample/upload-releases.sh
```

Если получили `internal server error` при загрузке debug-файлов, а в логах taskworker `FileNotFoundError: ... /var/lib/sentry/files/...` — filestore в режиме `filesystem` (PVC RWO) доступен только web-поду. Переключите на S3-бэкенд (Yandex Object Storage), см. **§3.2**.

Для нативного примера: после успешного выполнения файлы видны в **Project Settings → Debug Information Files**; имена релизов — в разделе **Releases**. Нативные DIF в Sentry сопоставляются с событием по **debug id** (build-id), а не по имени релиза; подробности — в комментариях в начале скрипта.

#### JS source maps (только загрузка артефактов)

В [examples/sourcemap-upload](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/examples/sourcemap-upload) — минифицированный бандл (`esbuild`) и загрузка **source maps** в релиз через `sentry-cli releases files … upload-sourcemaps`. Отдельный сервис в примере не поднимается; чтобы стеки в UI совпали с картами, в браузерном SDK укажите тот же `**release`**, что и `SENTRY_RELEASE` при upload. Где в интерфейсе смотреть загруженные файлы — в [README примера](https://github.com/patsevanton/sentry-v29-yc-k8s-elastic/blob/master/examples/sourcemap-upload/README.md) (**Releases** → нужный релиз → **Artifacts** / **Files**).

```bash
export SENTRY_URL="http://sentry.apatsev.org.ru"
export SENTRY_AUTH_TOKEN="<SENTRY_AUTH_TOKEN>"
export SENTRY_ORG="sentry"
export SENTRY_PROJECT="<slug проекта>"
bash examples/sourcemap-upload/upload-sourcemaps.sh
```

