# Развёртывание Sentry v29.5.1 в Yandex Cloud на Kubernetes

### 0. NodeLocal DNSCache (опционально)

[NodeLocal DNSCache](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/) — кэш DNS на каждом узле (DaemonSet в `kube-system`), снижает задержки и нагрузку на CoreDNS. В манифесте [k8s/nodelocaldns.yaml](k8s/nodelocaldns.yaml) в блоке `.:53` плейсхолдер `**__SENTRY_INGRESS_IP__**` нужно заменить на текущий внешний IP из `terraform output -raw ingress_public_ip` (тот же адрес, что резервирует [ip-dns.tf](ip-dns.tf) и куда указывают A-записи), чтобы поды резолвили тот же адрес, что и публичный DNS, даже если внешний DNS из кластера недоступен.

**Установка** (опционально). Нужен настроенный `kubectl` на кластер. Подставляется ClusterIP сервиса кластерного DNS (`kube-dns`), затем манифест применяется через `kubectl apply -f -`. Режим **iptables** у kube-proxy — типичный случай.

```bash
kubedns=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}')
domain=cluster.local
localdns=169.254.20.10
ingress_ip=$(terraform output -raw ingress_public_ip)
sed -e "s/__PILLAR__LOCAL__DNS__/${localdns}/g" \
    -e "s/__PILLAR__DNS__DOMAIN__/${domain}/g" \
    -e "s/__PILLAR__DNS__SERVER__/${kubedns}/g" \
    -e "s/__SENTRY_INGRESS_IP__/${ingress_ip}/g" \
    k8s/nodelocaldns.yaml | kubectl apply -f -
```

Если kube-proxy в режиме **IPVS**, используйте подстановку из [документации](https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/) (в т.ч. удаление `,__PILLAR__DNS__SERVER__` из `bind` и замена `__PILLAR__CLUSTER__DNS__`); для IPVS обычно меняют `--cluster-dns` у kubelet на адрес NodeLocal (`169.254.20.10`).

Проверка из пода:

```bash
kubectl run -it --rm dns-test --image=busybox:1.36 --restart=Never -- nslookup sentry.apatsev.org.ru
# ожидается IP из: terraform output -raw ingress_public_ip
```

### 1. Elasticsearch (nodestore) и оператор ECK

Nodestore хранит «сырые» узлы событий; здесь используется [sentry-nodestore-elastic](https://pypi.org/project/sentry-nodestore-elastic/) и кластер **Elasticsearch 9.x** через [ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html). Чарт Sentry не ставит `sentry-nodestore-elastic` сам, поэтому нужен **кастомный образ** на базе `ghcr.io/getsentry/sentry` ([реестр](https://github.com/getsentry/sentry/pkgs/container/sentry); образ `getsentry/sentry` на Docker Hub помечен как deprecated) — см. [Dockerfile.sentry-nodestore](Dockerfile.sentry-nodestore). На PyPI у пакета ограничение `elasticsearch<9` (Python-клиент); для кластера **9.x** клиент **9.x** в образе ставится отдельно (комментарии в `Dockerfile.sentry-nodestore`).

**1.1. Оператор Elasticsearch (ECK)**

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

**1.2. Кластер Elasticsearch 9.x**

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

После того как кластер из **§1.2** в статусе `Ready`:

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

**1.4. Образ Sentry с nodestore**

В этом репозитории образ **уже собран** и публикуется в GHCR; для установки по примеру из README достаточно указать его в Helm values — см. [values-sentry-minimal.yaml](values-sentry-minimal.yaml) (`images.sentry.repository` и `images.sentry.tag`).

Если вы **сами** собираете образ (другой реестр, свои правки в `Dockerfile.sentry-nodestore` или обновление под новый релиз чарта), делайте так:

```bash
docker build -f Dockerfile.sentry-nodestore -t <registry>/<имя>:<тег> .
docker push <registry>/<имя>:<тег>
```

Тег образа Sentry должен соответствовать версии приложения в чарте (см. **1.6**). В `values` при установке:

```yaml
images:
  sentry:
    repository: <registry>/<имя>
    tag: "<тег>"
```

**1.5. Интеграция nodestore в Sentry**

В `config.sentryConfPy` в [values-sentry-minimal.yaml](values-sentry-minimal.yaml) (или в своём values поверх него) задайте клиент и приложение Django, например для HTTP без TLS (как в манифесте ECK выше). Готовый пример — тот же файл:

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

Установка или обновление релиза с nodestore — один values-файл с образом и `config.sentryConfPy` ([values-sentry-minimal.yaml](values-sentry-minimal.yaml)). Саму команду `helm upgrade` и инициализацию nodestore выполняйте один раз после **§2** (ClickHouse) и **§3** (репозиторий Helm) — см. **§4**.

**1.6. TLS и версии**

- Для HTTPS и аутентификации настройте Elasticsearch по [документации Elastic](https://www.elastic.co/guide/en/elasticsearch/reference/current/configuring-security.html) и используйте `basic_auth` / `ssl_assert_fingerprint` в клиенте Python — см. [PyPI sentry-nodestore-elastic](https://pypi.org/project/sentry-nodestore-elastic/).
- Версия образа Sentry должна совпадать с `appVersion` чарта Sentry (`helm show chart sentry/sentry --version <ver>`).
- Кластер **9.x** и образ с **elasticsearch-py 9.x** согласованы с [elasticsearch.yaml](elasticsearch.yaml) и `Dockerfile.sentry-nodestore`.

### 2. ClickHouse

**2.1. Установка Altinity ClickHouse Operator**

```bash
helm repo add altinity https://helm.altinity.com
helm repo update
helm upgrade --install clickhouse-operator altinity/altinity-clickhouse-operator \
  --version 0.26.2 \
  --namespace clickhouse-operator \
  --create-namespace \
  --wait
```

Оператор через `ClickHouseOperatorConfiguration` будет наблюдать за namespace `clickhouse`.

```bash
kubectl apply -n clickhouse-operator -f clickhouse-operator-config.yaml
```

Перезапуск оператора, чтобы подхватить `ClickHouseOperatorConfiguration`. Подробнее в [issue #1930](https://github.com/Altinity/clickhouse-operator/issues/1930).

```bash
kubectl rollout restart deployment/clickhouse-operator-altinity-clickhouse-operator -n clickhouse-operator
```

Имя deployment задаёт Helm (release `clickhouse-operator` + chart `altinity-clickhouse-operator`). При другом `--name` релиза смотрите: `kubectl get deploy -n clickhouse-operator`.

**2.2. Создание ClickHouse**

```bash
kubectl create namespace clickhouse
kubectl apply -f clickhouse.yaml
```

Дождитесь готовности пода. Оператор создаёт под с именем вида `chi-sentry-clickhouse-single-node-0-0-0` (StatefulSet `…-0-0`, ординал StatefulSet — ещё `-0`); DNS в `externalClickhouse.host` — сервис `chi-sentry-clickhouse-single-node-0-0` в [values-sentry-minimal.yaml](values-sentry-minimal.yaml), это не имя пода. Удобнее ждать по label CHI:

```bash
kubectl -n clickhouse wait --for=condition=ready pod -l clickhouse.altinity.com/chi=sentry-clickhouse --timeout=600s
```

### 3. Репозиторий Sentry

Подключите Helm-репозиторий чарта Sentry. Namespace `sentry` можно создать заранее или при установке в **§4** флагом `--create-namespace`.

```bash
kubectl create namespace sentry
helm repo add sentry https://sentry-kubernetes.github.io/charts
helm repo update
```

Если namespace уже есть, `kubectl create namespace sentry` завершится ошибкой — это нормально. Либо опустите эту строку и полагайтесь только на `--create-namespace` у Helm.

### 4. Установка Sentry

**Порядок зависимостей.** Чарт поднимает PostgreSQL, Redis и Kafka в namespace `sentry`, но **ClickHouse задаётся снаружи** ([values-sentry-minimal.yaml](values-sentry-minimal.yaml), `externalClickhouse`). Helm-hook **Job `sentry-db-check`** ждёт TCP до `externalClickhouse.host:9000` и до Kraft-контроллеров Kafka. Пока ClickHouse не развёрнут, в логах пода будет `nc: getaddrinfo: Name does not resolve` и `... is not available yet` — это нормально только до выполнения **§2** (namespace `clickhouse`, [clickhouse.yaml](clickhouse.yaml), под ClickHouse в статусе `Running`, см. команду `wait` выше). Сначала: **§1.1–1.2** (Elasticsearch), **§2.1–2.2** (ClickHouse), **§3** (репозиторий Helm), затем команда ниже.

Установка с [values-sentry-minimal.yaml](values-sentry-minimal.yaml): в файле уже заданы nodestore в Elasticsearch (`images.sentry`, `config.sentryConfPy`). Перед `helm upgrade` разверните оператор и кластер из **§1.1–1.2** ([elasticsearch.yaml](elasticsearch.yaml)).

```bash
helm upgrade --install sentry sentry/sentry --version 29.5.1 -n sentry \
  -f values-sentry-minimal.yaml --timeout=900s --create-namespace
```

После первого подключения к Elasticsearch инициализируйте шаблон индекса nodestore:

```bash
kubectl -n sentry exec -it deploy/sentry-web -- sentry upgrade --with-nodestore
```

Зайти в Sentry в браузере: **[http://sentry.apatsev.org.ru](http://sentry.apatsev.org.ru)** (DNS и ingress — **§8**; если задали другой хост в Ingress/`values`, используйте его).

Пакет `sentry-nodestore-elastic` относится к **sentry-web** и воркерам на том же образе. **Relay** и **taskbroker** отдельно не настраиваются. Для **Snuba** при необходимости см. [Dockerfile.snuba-nodestore](Dockerfile.snuba-nodestore).

Свой образ и правки nodestore — по **§1.4–1.5** (в том же `values-sentry-minimal.yaml` или в дополнительном `-f` при необходимости). Репозиторий Helm — **§3** (выполните до первой установки).

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
kubectl -n vmks get secret vmks-grafana -o jsonpath='{.data.admin-password}' | base64 -d
echo
```

Логин по умолчанию — `**admin**` (его можно прочитать из ключа `admin-user` того же Secret). Если вы установили стек под другим именем релиза, замените `vmks-grafana` на `<ваш-релиз>-grafana`.

Для имён из `vmks-values.yaml` (`vmsingle.apatsev.org.ru`, `grafana.apatsev.org.ru`) добавьте **A-записи** на тот же внешний IP, что у ingress (см. [ip-dns.tf](ip-dns.tf) для `sentry.apatsev.org.ru`).

Интеграция с экспортёром Sentry — шаг 4 в **§7** и манифест [k8s/vmscrape-sentry-prometheus-exporter.yaml](k8s/vmscrape-sentry-prometheus-exporter.yaml).

### 7. Мониторинг Sentry (Prometheus exporter)

После установки Sentry (**§4**, namespace `sentry`) и VictoriaMetrics K8s Stack (**§6**) можно поднять [sentry-prometheus-exporter](https://github.com/italux/sentry-prometheus-exporter) манифестом [k8s/sentry-prometheus-exporter.yaml](k8s/sentry-prometheus-exporter.yaml): метрики на порту **9790**, путь `/metrics`. Внутри кластера API Sentry задаётся как `http://sentry-web.sentry.svc.cluster.local:9000/api/0/`. В Deployment переменная `**SENTRY_EXPORTER_ORG`** должна совпадать со **slug организации** в UI (путь `/organizations/<slug>/`); в файле по умолчанию указано `sentry` — при необходимости отредактируйте перед `kubectl apply`.

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

4. Подключите scrape через `VMServiceScrape`: [k8s/vmscrape-sentry-prometheus-exporter.yaml](k8s/vmscrape-sentry-prometheus-exporter.yaml) (`kubectl apply -f k8s/vmscrape-sentry-prometheus-exporter.yaml`). Либо укажите цель вручную, например `http://sentry-prometheus-exporter.sentry.svc.cluster.local:9790/metrics`.

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
  --from-literal=dsn='http://6b1c066bb1cec1f9b0bf7fd45a4f1d52@sentry.apatsev.org.ru/2'
kubectl create secret generic sentry-dsn-python -n demo-sentry \
  --from-literal=dsn='http://65d983c09b9bc4c23fc332b76bc7de27@sentry.apatsev.org.ru/3'
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

Перед запуском задайте URL self-hosted (если не дефолтный `sentry.io`), организацию, проект и токен с правами на загрузку артефактов / релизов (см. комментарии в скрипте):

```bash
export SENTRY_URL="http://sentry.apatsev.org.ru"   # при необходимости
export SENTRY_AUTH_TOKEN="<токен>"
export SENTRY_ORG="<slug организации>"
export SENTRY_PROJECT="<slug проекта>"

bash examples/sentry-native-debug-sample/upload-releases.sh
```

Для нативного примера: после успешного выполнения файлы видны в **Project Settings → Debug Information Files**; имена релизов — в разделе **Releases**. Нативные DIF в Sentry сопоставляются с событием по **debug id** (build-id), а не по имени релиза; подробности — в комментариях в начале скрипта.

#### JS source maps (только загрузка артефактов)

В [examples/sourcemap-upload](examples/sourcemap-upload) — минифицированный бандл (`esbuild`) и загрузка **source maps** в релиз через `sentry-cli releases files … upload-sourcemaps`. Отдельный сервис в примере не поднимается; чтобы стеки в UI совпали с картами, в браузерном SDK укажите тот же `**release`**, что и `SENTRY_RELEASE` при upload. Где в интерфейсе смотреть загруженные файлы — в [README примера](examples/sourcemap-upload/README.md) (**Releases** → нужный релиз → **Artifacts** / **Files**).

```bash
export SENTRY_URL="http://sentry.apatsev.org.ru"
export SENTRY_AUTH_TOKEN="<токен>"
export SENTRY_ORG="<slug организации>"
export SENTRY_PROJECT="<slug проекта>"
bash examples/sourcemap-upload/upload-sourcemaps.sh
```

