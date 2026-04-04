# Развёртывание Sentry v29.5.1 в Yandex Cloud на Kubernetes

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

ECK создаёт HTTP-сервис **`<имя-ресурса>-es-http`**. Для `metadata.name: sentry-nodestore` это `sentry-nodestore-es-http`. Полный DNS из подов в `sentry`:

`sentry-nodestore-es-http.elasticsearch.svc.cluster.local:9200`

В манифесте отключены TLS на HTTP и встроенная security Elasticsearch: это упрощает минимальный сценарий — nodestore в Sentry подключается по обычному `http://` без выдачи сертификатов, доверия к CA и без логина и пароля в `sentryConfPy`; трафик к API Elasticsearch остаётся внутри сети кластера.

**1.3. Образ Sentry с nodestore**

В этом репозитории образ **уже собран** и публикуется в GHCR; для установки по примеру из README достаточно указать его в Helm values — см. [values-sentry-minimal.yaml](values-sentry-minimal.yaml) (`images.sentry.repository` и `images.sentry.tag`).

Если вы **сами** собираете образ (другой реестр, свои правки в `Dockerfile.sentry-nodestore` или обновление под новый релиз чарта), делайте так:

```bash
docker build -f Dockerfile.sentry-nodestore -t <registry>/<имя>:<тег> .
docker push <registry>/<имя>:<тег>
```

Тег образа Sentry должен соответствовать версии приложения в чарте (см. **1.5**). В `values` при установке:

```yaml
images:
  sentry:
    repository: <registry>/<имя>
    tag: "<тег>"
```

**1.4. Интеграция nodestore в Sentry**

В `config.sentryConfPy` в [values-sentry-minimal.yaml](values-sentry-minimal.yaml) (или в своём values поверх него) задайте клиент и приложение Django, например для HTTP без TLS (как в манифесте ECK выше). Готовый пример — тот же файл:

```python
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

from sentry.conf.server import *

INSTALLED_APPS = list(INSTALLED_APPS)
INSTALLED_APPS.append("sentry_nodestore_elastic")
INSTALLED_APPS = tuple(INSTALLED_APPS)
```

Установка или обновление релиза с nodestore — один values-файл с образом и `config.sentryConfPy` ([values-sentry-minimal.yaml](values-sentry-minimal.yaml)). Перед `helm upgrade` подключите репозиторий чарта (**§3**). Namespace `sentry` создаётся флагом `--create-namespace` (если уже создали вручную в **§3**, флаг не мешает):

```bash
helm upgrade --install sentry sentry/sentry --version 29.5.1 -n sentry \
  -f values-sentry-minimal.yaml --timeout=900s --create-namespace
```

После первого подключения к Elasticsearch инициализируйте шаблон индекса nodestore:

```bash
kubectl -n sentry exec -it deploy/sentry-web -- sentry upgrade --with-nodestore
```

Пакет `sentry-nodestore-elastic` относится к **sentry-web** и воркерам на том же образе. **Relay** и **taskbroker** отдельно не настраиваются. Для **Snuba** при необходимости см. [Dockerfile.snuba-nodestore](Dockerfile.snuba-nodestore).

**1.5. TLS и версии**

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
kubectl rollout status deployment/clickhouse-operator-altinity-clickhouse-operator -n clickhouse-operator --timeout=1m
```

Имя deployment задаёт Helm (release `clickhouse-operator` + chart `altinity-clickhouse-operator`). При другом `--name` релиза смотрите: `kubectl get deploy -n clickhouse-operator`.

**2.2. Создание ClickHouse**

```bash
kubectl create namespace clickhouse
kubectl apply -f clickhouse.yaml
```

Дождитесь готовности пода (имя совпадает с `externalClickhouse.host` в values — для [clickhouse.yaml](clickhouse.yaml) это `chi-sentry-clickhouse-single-node-0-0`):

```bash
kubectl -n clickhouse wait --for=condition=ready pod/chi-sentry-clickhouse-single-node-0-0 --timeout=600s
```

### 3. Репозиторий Sentry

Подключите Helm-репозиторий чарта Sentry. Namespace `sentry` можно создать заранее или при установке в **§1.4** / **§4** флагом `--create-namespace`.

```bash
kubectl create namespace sentry
helm repo add sentry https://sentry-kubernetes.github.io/charts
helm repo update
```

Если namespace уже есть, `kubectl create namespace sentry` завершится ошибкой — это нормально. Либо опустите эту строку и полагайтесь только на `--create-namespace` у Helm.

### 4. Установка Sentry

**Порядок зависимостей.** Чарт поднимает PostgreSQL, Redis и Kafka в namespace `sentry`, но **ClickHouse задаётся снаружи** ([values-sentry-minimal.yaml](values-sentry-minimal.yaml), `externalClickhouse`). Helm-hook **Job `sentry-db-check`** ждёт TCP до `externalClickhouse.host:9000` и до Kraft-контроллеров Kafka. Пока ClickHouse не развёрнут, в логах пода будет `nc: getaddrinfo: Name does not resolve` и `... is not available yet` — это нормально только до выполнения **§2** (namespace `clickhouse`, [clickhouse.yaml](clickhouse.yaml), под `chi-sentry-clickhouse-single-node-0-0` в статусе `Running`). Сначала: **§1.1–1.2** (Elasticsearch), **§2.1–2.2** (ClickHouse), **§3** (репозиторий Helm), затем команда ниже.

Установка с [values-sentry-minimal.yaml](values-sentry-minimal.yaml): в файле уже заданы nodestore в Elasticsearch (`images.sentry`, `config.sentryConfPy`). Перед `helm upgrade` разверните оператор и кластер из **§1.1–1.2** ([elasticsearch.yaml](elasticsearch.yaml)).

```bash
helm upgrade --install sentry sentry/sentry --version 29.5.1 -n sentry \
  -f values-sentry-minimal.yaml --timeout=900s --create-namespace
```

Свой образ и правки nodestore — по **§1.3–1.4** (в том же `values-sentry-minimal.yaml` или в дополнительном `-f` при необходимости). Репозиторий Helm — **§3** (выполните до первой установки).

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

### 6. Доступ к Sentry

Sentry доступен по адресу **http://sentry.apatsev.org.ru** через [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) (стандартный `Ingress`).

Убедитесь, что DNS-запись `sentry.apatsev.org.ru` указывает на внешний IP сервиса ingress-nginx (обычно `LoadBalancer` в namespace `ingress-nginx`):

```bash
kubectl -n ingress-nginx get svc
```
