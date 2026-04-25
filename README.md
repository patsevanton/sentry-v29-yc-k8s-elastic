# Развёртывание Sentry v30.1.0 в Yandex Cloud на Kubernetes

## Цели статьи

Статья описывает процесс развёртывания Sentry v30.1.0 в Yandex Cloud на кластере Kubernetes. Будет развёрнуто:

- Инфраструктура через Terraform (K8S, ClickHouse, PostgreSQL, Object Storage, VPC).
- Elasticsearch 9.x через ECK Operator для nodestore.
- Sentry в Kubernetes через Helm-чарт.
- S3 filestore (Yandex Object Storage) для артефактов Sentry.
- KEDA — автоскейлинг воркеров Sentry по глубине Kafka-очередей.
- VictoriaMetrics K8s Stack (VMSingle, VMAgent, Grafana, vmalert, node-exporter, kube-state-metrics).
- Мониторинг Sentry через Prometheus exporter и VMServiceScrape.
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

### 0. Managed ClickHouse (Yandex Cloud)

ClickHouse используется только как внешний managed-кластер в Yandex Cloud. Terraform создаёт Managed ClickHouse и автоматически подставляет endpoint/креды в `values_sentry.yaml` (через `values_sentry.yaml.tpl`):
- кластер: `yandex_mdb_clickhouse_cluster.managed`;
- база: `clickhousedbops_database.managed_sentry` (при SQL user management);
- пользователь: `clickhousedbops_user.managed_sentry` или `yandex_mdb_clickhouse_user.managed_sentry` (в зависимости от режима SQL user management).

Пароль пользователя managed CH можно задать явно:

```hcl
managed_clickhouse_user_password = "<SECRET>"
```

Если не задавать `managed_clickhouse_user_password`, Terraform сгенерирует случайный пароль автоматически.

Перед `helm upgrade` проверьте DNS из pod (если в `system.clusters` есть short hostnames):

```bash
kubectl -n sentry run -it --rm dns-test --image=busybox:1.36 --restart=Never -- nslookup <host_name_из_system.clusters>
```

Если short hostnames не резолвятся, включите в Terraform `enable_clickhouse_dns_search=true`.

**Важно про distributed + non-TLS (вывод из проверки `system.clusters`).**

На текущем Yandex Managed ClickHouse в `system.clusters` для `clusterName=default` опубликован только порт `9440` (TLS):

```
┌─cluster─┬─host_name─────────────────────────────────┬─port─┬─shard_num─┬─replica_num─┐
│ default │ rc1a-3s788r2f9setaa1o.mdb.yandexcloud.net │ 9440 │         1 │           1 │
│ default │ rc1b-j5i5388j1nhdhuc5.mdb.yandexcloud.net │ 9440 │         1 │           2 │
│ default │ rc1d-rbcg9hhifci2e797.mdb.yandexcloud.net │ 9440 │         1 │           3 │
└─────────┴───────────────────────────────────────────┴──────┴───────────┴─────────────┘
```

Это означает:
- при `external_clickhouse_single_node=false` Snuba использует `system.clusters` для distributed-операций;
- комбинация `single_node=false` + `tcpPort=9000` + **NO TLS** с этим MCH не работает;
- чтобы сохранить distributed (HA), нужен TLS/`9440`;
- чтобы использовать NO TLS/`9000` в distributed-режиме, нужно использовать [ClickHouse Operator](https://github.com/Altinity/clickhouse-operator) в k8s, где `system.clusters` отдаёт порт `9000`.

### 1. NodeLocal DNSCache (опционально)

[NodeLocal DNSCache](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/) — кэш DNS на каждом узле (DaemonSet в `kube-system`), снижает задержки и нагрузку на CoreDNS. В манифесте [k8s/nodelocaldns.yaml](k8s/nodelocaldns.yaml) в блоке `.:53` плейсхолдер `**__SENTRY_INGRESS_IP__**` нужно заменить на текущий внешний IP из `terraform output -raw ingress_public_ip` (тот же адрес, что резервирует [ip-dns.tf](ip-dns.tf) и куда указывают A-записи), чтобы поды резолвили тот же адрес, что и публичный DNS, даже если внешний DNS из кластера недоступен.

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

### 2. Elasticsearch (nodestore) и оператор ECK

Nodestore хранит «сырые» узлы событий; здесь используется [sentry-nodestore-elastic](https://pypi.org/project/sentry-nodestore-elastic/) и кластер **Elasticsearch 9.x** через [ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html). Чарт Sentry не ставит `sentry-nodestore-elastic` сам, поэтому нужен **кастомный образ** на базе `ghcr.io/getsentry/sentry` ([реестр](https://github.com/getsentry/sentry/pkgs/container/sentry) — см. [Dockerfile.sentry-nodestore](Dockerfile.sentry-nodestore). На PyPI у пакета ограничение `elasticsearch<9` (Python-клиент); для кластера **9.x** клиент **9.x** в образе ставится отдельно (комментарии в `Dockerfile.sentry-nodestore`).

**2.1. Оператор Elasticsearch (ECK)**

Установите [ECK Operator](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/install-using-yaml-manifest-quickstart) из Helm-чарта [deploy/eck-operator](https://github.com/elastic/cloud-on-k8s/tree/v3.3.2/deploy/eck-operator) репозитория [elastic/cloud-on-k8s](https://github.com/elastic/cloud-on-k8s) (тег **v3.3.2**).

```bash
kubectl create namespace eck-operator

git clone --depth 1 --branch v3.3.2 \
  https://github.com/elastic/cloud-on-k8s.git cloud-on-k8s
helm template elastic-operator cloud-on-k8s/deploy/eck-operator \
  -n eck-operator \
  | kubectl apply -f -
rm -rf cloud-on-k8s
```

**2.2. Кластер Elasticsearch 9.x**

Манифест кластера — [elasticsearch.yaml](elasticsearch.yaml).

```bash
kubectl create namespace elasticsearch
kubectl apply -f elasticsearch.yaml
```

Проверка готовности:

```bash
kubectl -n elasticsearch get elasticsearch.elasticsearch.k8s.elastic.co sentry-nodestore
kubectl -n elasticsearch get pods,svc
```

ECK создаёт HTTP-сервис `**<имя-ресурса>-es-http**`. Для `metadata.name: sentry-nodestore` это `sentry-nodestore-es-http`. Полный DNS из подов в `sentry`:

`sentry-nodestore-es-http.elasticsearch.svc.cluster.local:9200`

В манифесте отключены TLS на HTTP и встроенная security Elasticsearch: это упрощает минимальный сценарий — nodestore в Sentry подключается по обычному `http://` без выдачи сертификатов, доверия к CA и без логина и пароля в `sentryConfPy`; трафик к API Elasticsearch остаётся внутри сети кластера.

**1.3. ILM: удаление старых данных (опционально)**

Манифест [index-lifecycle-policy-delete.yaml](index-lifecycle-policy-delete.yaml) задаёт политику ILM с фазой `delete` через ресурс `StackConfigPolicy` (ECK **3.3+**). Для [Elastic Stack configuration policies](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-stack-config-policy.html) в ECK нужна лицензия **Enterprise** или **trial** ([лицензии в ECK](https://www.elastic.co/docs/deploy-manage/license/manage-your-license-in-eck)).

После того как кластер из **§2.2** в статусе `Ready`:

```bash
kubectl apply -f index-lifecycle-policy-delete.yaml
```

Политика в `namespace: elasticsearch` без `resourceSelector` применяется ко всем кластерам Elasticsearch в этом namespace (в т.ч. к `sentry-nodestore`). Оператор создаёт в Elasticsearch именованную политику `index-lifecycle-policy-delete` (удаление через **20 дней** после `min_age`). Чтобы ретенция реально действовала на индексы nodestore, политику нужно **привязать** к ним (index template, `index.lifecycle.name` или `PUT` настроек индекса) — само наличие ILM в кластере не меняет существующие индексы без привязки.

Проверка:

```bash
kubectl -n elasticsearch get stackconfigpolicy index-lifecycle-policy-delete
# из пода в кластере, при необходимости:
curl -s "http://sentry-nodestore-es-http.elasticsearch.svc.cluster.local:9200/_ilm/policy/index-lifecycle-policy-delete"
```

**2.4. Образ Sentry с nodestore**

В этом репозитории образ **уже собран** и публикуется в GHCR; для установки по примеру из README достаточно указать его в Helm values — см. [values_sentry.yaml.tpl](values_sentry.yaml.tpl) (`images.sentry.repository` и `images.sentry.tag`). Файл `values_sentry.yaml` генерируется автоматически из шаблона через Terraform (см. [templatefile.tf](templatefile.tf)).

Если вы **сами** собираете образ (другой реестр, свои правки в `Dockerfile.sentry-nodestore` или обновление под новый релиз чарта), делайте так:

```bash
docker build -f Dockerfile.sentry-nodestore -t <registry>/<имя>:<тег> .
docker push <registry>/<имя>:<тег>
```

Тег образа Sentry должен соответствовать версии приложения в чарте (см. **2.6**). В `values` при установке:

```yaml
images:
  sentry:
    repository: <registry>/<имя>
    tag: "<тег>"
```

**2.5. Интеграция nodestore в Sentry**

В `config.sentryConfPy` в [values_sentry.yaml.tpl](values_sentry.yaml.tpl) (или в своём values поверх него) задайте клиент и приложение Django, например для HTTP без TLS (как в манифесте ECK выше). Готовый пример — тот же файл:

```python
# Не импортируйте sentry.conf.server здесь: фрагмент дописывается в конец sentry.conf.py
# чарта; повторный import * обнуляет SENTRY_CACHE (ошибка cache.backend).
from elasticsearch import Elasticsearch

es = Elasticsearch(
    ["http://sentry-nodestore-es-http.elasticsearch.svc.cluster.local:9200"],
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
```

Установка или обновление релиза с nodestore — один values-файл с образом и `config.sentryConfPy` (`values_sentry.yaml`, генерируется из [values_sentry.yaml.tpl](values_sentry.yaml.tpl)). Саму команду `helm upgrade` и инициализацию nodestore выполняйте один раз после **§0** (ClickHouse) и **§3** (репозиторий Helm) — см. **§4**.

**2.6. TLS и версии**

- Для HTTPS и аутентификации настройте Elasticsearch по [документации Elastic](https://www.elastic.co/guide/en/elasticsearch/reference/current/configuring-security.html) и используйте `basic_auth` / `ssl_assert_fingerprint` в клиенте Python — см. [PyPI sentry-nodestore-elastic](https://pypi.org/project/sentry-nodestore-elastic/).
- Версия образа Sentry должна совпадать с `appVersion` чарта Sentry (`helm show chart sentry/sentry --version <ver>`).
- Кластер **9.x** и образ с **elasticsearch-py 9.x** согласованы с [elasticsearch.yaml](elasticsearch.yaml) и `Dockerfile.sentry-nodestore`.

### 3. Репозиторий Sentry

Подключите Helm-репозиторий чарта Sentry. Namespace `sentry` можно создать заранее или при установке в **§4** флагом `--create-namespace`.

```bash
kubectl create namespace sentry
helm repo add sentry https://sentry-kubernetes.github.io/charts
helm repo update
```

Если namespace уже есть, `kubectl create namespace sentry` завершится ошибкой — это нормально. Либо опустите эту строку и полагайтесь только на `--create-namespace` у Helm.

### 3.1. KEDA (автоскейлинг по Kafka lag)

Для автоскейлинга воркеров Sentry по глубине Kafka-очередей установите [KEDA](https://keda.sh/) в отдельный namespace.

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

### 3.2. S3 filestore (Yandex Object Storage)

По умолчанию чарт Sentry хранит артефакты (debug-символы, source maps, blob-ы загрузок) на локальной ФС (`/var/lib/sentry/files`) с PVC в режиме **RWO** (ReadWriteOnce). RWO-том доступен только одному поду (обычно `sentry-web`); taskworker-ы при сборке (`assemble`) debug-файлов не находят blob-ы → `FileNotFoundError` / `internal server error` в UI. S3-бэкенд доступен всем подам одновременно.

Terraform-файл [s3.tf](s3.tf) создаёт сервисный аккаунт, статический ключ и бакет в Yandex Object Storage:

```bash
terraform apply
```

После apply файл `values_sentry.yaml` генерируется автоматически из шаблона [values_sentry.yaml.tpl](values_sentry.yaml.tpl) через Terraform (см. [templatefile.tf](templatefile.tf)) — ключи S3 подставляются из ресурсов Terraform, ручная подстановка не нужна.

### 4. Установка Sentry

**Порядок зависимостей.** Чарт поднимает PostgreSQL, Redis и Kafka в namespace `sentry`, а **ClickHouse задаётся снаружи** (`externalClickhouse` в [values_sentry.yaml.tpl](values_sentry.yaml.tpl)). Сначала выполните **§2.1–2.2** (Elasticsearch), **§0** (Managed ClickHouse через Terraform), **§3** (репозиторий Helm), затем команду ниже.

Установка с `values_sentry.yaml` (генерируется из [values_sentry.yaml.tpl](values_sentry.yaml.tpl) через `terraform apply`): в файле уже заданы nodestore в Elasticsearch (`images.sentry`, `config.sentryConfPy`) и параметры Managed ClickHouse из Terraform outputs.

```bash
helm upgrade --install sentry sentry/sentry --version 30.1.0 -n sentry \
  -f values_sentry.yaml --timeout=3600s --create-namespace
```

**Устанавливается долго:** первый `helm upgrade --install` часто занимает 20–40 минут и более — последовательно выполняются Job’ы (проверка/инициализация БД, provisioning Kafka, Snuba и миграции). Увеличенный timeout (`3600s` = 1 час) позволяет избежать прерывания установки при длительном выполнении Job. Смотрите `kubectl -n sentry get jobs` и логи подов Job при зависаниях. Пример строк (реальный прогон; в k9s колонка **AGE** часто отсортирована по возрастанию — значок **↑**):

| NAMESPACE | NAME | COMPLETIONS | DURATION | AGE |
|-----------|------|-------------|----------|-----|
| sentry | sentry-user-create | 1/1 | 14s | 18s |
| sentry | sentry-db-init | 1/1 | 2m2s | 2m21s |
| sentry | sentry-snuba-db-init | 1/1 | 6s | 16m |
| sentry | sentry-snuba-migrate | 1/1 | 13m | 16m |
| sentry | sentry-kafka-provisioning | 1/1 | 10m | 26m |
| sentry | sentry-db-check | 1/1 | 2m50s | 29m |

После первого подключения к Elasticsearch инициализируйте шаблон индекса nodestore:

```bash
kubectl -n sentry exec -it deploy/sentry-web -- sentry upgrade --with-nodestore
```

Зайти в Sentry в браузере: **[http://sentry.apatsev.org.ru](http://sentry.apatsev.org.ru)** (DNS и ingress — **§8**; если задали другой хост в Ingress/`values`, используйте его).

Пакет `sentry-nodestore-elastic` относится к **sentry-web** и воркерам на том же образе. **Relay** и **taskbroker** отдельно не настраиваются. Для **Snuba** при необходимости см. [Dockerfile.snuba-nodestore](Dockerfile.snuba-nodestore).

Свой образ и правки nodestore — по **§2.4–2.5** (в том же `values_sentry.yaml.tpl` или в дополнительном `-f` при необходимости). Репозиторий Helm — **§3** (выполните до первой установки).

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

Стек [VictoriaMetrics K8s Stack](https://docs.victoriametrics.com/helm/victoria-metrics-k8s-stack/) поднимает оператор VictoriaMetrics, **VMSingle**, **VMAgent**, **Grafana**, **vmalert**, Alertmanager, **node-exporter** и **kube-state-metrics**. Готовые значения — [vmks-values.yaml](vmks-values.yaml) (Ingress для UI хранилища и Grafana).

Нужен уже установленный **ingress-nginx** с классом `nginx` (в этом репозитории — Helm-релиз в [k8s.tf](k8s.tf)).

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

Для имён из `vmks-values.yaml` (`vmsingle.apatsev.org.ru`, `grafana.apatsev.org.ru`) добавьте **A-записи** на тот же внешний IP, что у ingress (см. [ip-dns.tf](ip-dns.tf) для `sentry.apatsev.org.ru`).

Интеграция с экспортёром Sentry — шаг 4 в **§7** и манифест [k8s/vmscrape-sentry-prometheus-exporter.yaml](k8s/vmscrape-sentry-prometheus-exporter.yaml).

### 7. Мониторинг Sentry (Prometheus exporter)

После установки Sentry (**§4**, namespace `sentry`) и VictoriaMetrics K8s Stack (**§6**) можно поднять [sentry-prometheus-exporter](https://github.com/italux/sentry-prometheus-exporter) манифестом [k8s/sentry-prometheus-exporter.yaml](k8s/sentry-prometheus-exporter.yaml): метрики на порту **9790**, путь `/metrics` (часто с редиректом на `/metrics/`). Внутри кластера API Sentry задаётся как `http://sentry-web.sentry.svc.cluster.local:9000/api/0/`. Переменная окружения `SENTRY_EXPORTER_ORG` должна быть равна **slug** организации — короткому идентификатору в URL (`/organizations/<slug>/`, тот же сегмент, что в запросах API `.../organizations/<slug>/`). Это не обязательно совпадает с **отображаемым именем** организации. В манифесте по умолчанию задано `sentry`: такой slug обычно у первой организации после мастера self-hosted Sentry; если в инстансе другая организация или slug — замените значение перед `kubectl apply`.

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

4. Подключите scrape через `VMServiceScrape`: [k8s/vmscrape-sentry-prometheus-exporter.yaml](k8s/vmscrape-sentry-prometheus-exporter.yaml) (`kubectl apply -f k8s/vmscrape-sentry-prometheus-exporter.yaml`). Манифест создаёт ресурс в namespace **`vmks`** (где работает `VMAgent` из §6) и указывает на Service в **`sentry`**; если положить `VMServiceScrape` только в `sentry`, vmagent его не подхватит. В нём же заданы `scrape_interval` / `scrapeTimeout` побольше: экспортёр отвечает медленно (запросы к API Sentry), иначе цель в vmagent будет **down** по таймауту. Либо укажите цель вручную, например `http://sentry-prometheus-exporter.sentry.svc.cluster.local:9790/metrics/`.

### 7.1. Мониторинг Yandex Managed Kafka в Grafana

Для Managed Kafka в Yandex Cloud метрики берутся напрямую из Yandex Monitoring endpoint `https://monitoring.api.cloud.yandex.net/monitoring/v2/prometheusMetrics` c параметрами `folderId` и `service=managed-kafka` (официальный export в формате Prometheus).

1. Создайте API key сервисного аккаунта с ролью `monitoring.viewer` на нужную папку в Yandex Cloud.
2. Получите значения переменных:

```bash
export FOLDER_ID=$(yc config get folder-id)
export MONITORING_API_KEY=$(yc iam create-key --service-account-name <имя-сервисного-аккаунта> --folder-id $FOLDER_ID --format json | jq -r '.secret')
```

3. Создайте Kubernetes Secret в namespace `vmks`:

```bash
kubectl -n vmks create secret generic yc-monitoring-api-key \
  --from-literal=bearer="$MONITORING_API_KEY"

cat > vmstaticscrape-yc-managed-kafka.yaml << EOF
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMStaticScrape
metadata:
  name: yc-managed-kafka
  namespace: vmks
spec:
  jobName: yc-managed-kafka
  targetEndpoints:
    - targets:
        - monitoring.api.cloud.yandex.net
      scheme: https
      path: /monitoring/v2/prometheusMetrics
      interval: 60s
      scrapeTimeout: 60s
      params:
        folderId:
          - "$FOLDER_ID"
        service:
          - "managed-kafka"
      authorization:
        bearer:
          name: yc-monitoring-api-key
          key: bearer
      labels:
        cloud: yandex
        service: managed-kafka
EOF
```

4. Примените сгенерированные манифесты:

```bash
kubectl apply -f vmstaticscrape-yc-managed-kafka.yaml
```

4. Проверьте, что vmagent видит target:

```bash
kubectl -n vmks get vmstaticscrape yc-managed-kafka
kubectl -n vmks get pods
```

5. Импортируйте дашборд [dashboard/yc-managed-kafka-overview.json](dashboard/yc-managed-kafka-overview.json) в Grafana (`Dashboards -> New -> Import`) и выберите datasource Prometheus/VictoriaMetrics.

5. Проверьте, что vmagent видит target:

```bash
kubectl -n vmks get vmstaticscrape yc-managed-kafka
kubectl -n vmks get pods
```

6. Импортируйте дашборд [dashboard/yc-managed-kafka-overview.json](dashboard/yc-managed-kafka-overview.json) в Grafana (`Dashboards -> New -> Import`) и выберите datasource Prometheus/VictoriaMetrics.

### 8. Доступ к Sentry

Sentry доступен по адресу **[http://sentry.apatsev.org.ru](http://sentry.apatsev.org.ru)** через [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) (стандартный `Ingress`).

Убедитесь, что DNS-запись `sentry.apatsev.org.ru` указывает на внешний IP сервиса ingress-nginx (обычно `LoadBalancer` в namespace `ingress-nginx`):

```bash
kubectl -n ingress-nginx get svc
```

### 9. Демо-клиенты Sentry

Два HTTP-сервиса (Python / FastAPI и Node.js / Express) с одинаковыми маршрутами для проверки self-hosted Sentry: исключения, сообщения, транзакции, breadcrumbs, контекст.

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
  --from-literal=dsn='http://043383a541f6f3f5d43e6e1f080d3352@sentry.apatsev.org.ru/2'
kubectl create secret generic sentry-dsn-python -n demo-sentry \
  --from-literal=dsn='http://709abdcff0f35b84e5d8d1e422454a68@sentry.apatsev.org.ru/3'
# либо подставить dsn в demo/k8s/secret-sentry-dsn-*.yaml и:
# kubectl apply -f demo/k8s/secret-sentry-dsn-node.yaml -f demo/k8s/secret-sentry-dsn-python.yaml

kubectl apply -f demo/k8s/deployment-python.yaml
kubectl apply -f demo/k8s/deployment-node.yaml
kubectl apply -f demo/k8s/service.yaml
```

Манифесты Secret с плейсхолдерами: `[demo/k8s/secret-sentry-dsn-node.yaml](demo/k8s/secret-sentry-dsn-node.yaml)`, `[demo/k8s/secret-sentry-dsn-python.yaml](demo/k8s/secret-sentry-dsn-python.yaml)`.

Переменная `DEMO_AUTO_EXCEPTION_INTERVAL_SEC` в манифестах demo (и при локальном запуске) задаёт интервал автоматической отправки исключений в Sentry; `0` отключает. Откройте проект в Sentry и убедитесь, что появились issues и (при включённом performance) транзакции.

#### Нативный пример (C, Linux ELF)

В [examples/sentry-native-debug-sample](examples/sentry-native-debug-sample) — минимальный `main.c` и скрипт [upload-releases.sh](examples/sentry-native-debug-sample/upload-releases.sh): сборка отладочного бинарника (`cc -g -O0`), создание имён релизов в Sentry и загрузка **debug information files** через `sentry-cli debug-files upload` (тип `elf`). Нужны установленные `**sentry-cli`** и компилятор `**cc**`.

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

В [examples/sourcemap-upload](examples/sourcemap-upload) — минифицированный бандл (`esbuild`) и загрузка **source maps** в релиз через `sentry-cli releases files … upload-sourcemaps`. Отдельный сервис в примере не поднимается; чтобы стеки в UI совпали с картами, в браузерном SDK укажите тот же `**release`**, что и `SENTRY_RELEASE` при upload. Где в интерфейсе смотреть загруженные файлы — в [README примера](examples/sourcemap-upload/README.md) (**Releases** → нужный релиз → **Artifacts** / **Files**).

```bash
export SENTRY_URL="http://sentry.apatsev.org.ru"
export SENTRY_AUTH_TOKEN="<SENTRY_AUTH_TOKEN>"
export SENTRY_ORG="sentry"
export SENTRY_PROJECT="<slug проекта>"
bash examples/sourcemap-upload/upload-sourcemaps.sh
```

