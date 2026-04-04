# Развёртывание Sentry v29.5.1 в Yandex Cloud на Kubernetes. 


обновить до 33 и использовать приемтив ноды
### 0. Подготовка

Создайте необходимые namespace и подключите необходимые Helm-репозитории (репозиторий Elastic для оператора ECK не нужен — установка из GitHub, см. **§1.1**).

```bash
kubectl create namespace clickhouse
```

**ingress-nginx** ставится вместе с кластером: в Terraform это `helm_release` в [k8s.tf](k8s.tf) (чарт Yandex Cloud Marketplace OCI, версия как в манифесте). Внешний IP сервиса задаётся через зарезервированный адрес (`controller.service.loadBalancerIP` → [yandex_vpc_address](ip-dns.tf)); при необходимости правьте ресурсы в `ip-dns.tf` и значения в `k8s.tf`.

### 1. Elasticsearch (nodestore) и оператор ECK

Nodestore хранит «сырые» узлы событий; здесь используется [sentry-nodestore-elastic](https://pypi.org/project/sentry-nodestore-elastic/) и кластер **Elasticsearch 9.x** через [ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html). Чарт Sentry не ставит `sentry-nodestore-elastic` сам (в отличие от nodestore S3), поэтому нужен **кастомный образ** на базе `ghcr.io/getsentry/sentry` ([реестр](https://github.com/getsentry/sentry/pkgs/container/sentry); образ `getsentry/sentry` на Docker Hub deprecated) — см. [Dockerfile.sentry-nodestore](Dockerfile.sentry-nodestore). На PyPI у пакета ограничение `elasticsearch<9` (Python-клиент); для кластера **9.x** клиент **9.x** в образе ставится отдельно (комментарии в `Dockerfile.sentry-nodestore`).

**1.1. Оператор Elasticsearch (ECK)**

Установите [ECK Operator](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s/install-using-yaml-manifest-quickstart) из Helm-чарта [deploy/eck-operator](https://github.com/elastic/cloud-on-k8s/tree/v3.3.2/deploy/eck-operator) репозитория [elastic/cloud-on-k8s](https://github.com/elastic/cloud-on-k8s) (тег **v3.3.2**).

```bash
kubectl create namespace elastic-system

git clone --depth 1 --branch v3.3.2 --filter=blob:none --sparse \
  https://github.com/elastic/cloud-on-k8s.git cloud-on-k8s
git -C cloud-on-k8s sparse-checkout set deploy/eck-operator
helm template elastic-operator cloud-on-k8s/deploy/eck-operator \
  -n elastic-system \
  | kubectl apply -f -
rm -rf cloud-on-k8s
```

**1.2. Кластер Elasticsearch 9.x**

Elasticsearch на Kubernetes проверяет **`vm.max_map_count` на ноде** (нужно не ниже **262144**; иначе контейнер падает с bootstrap check и кодом выхода 78). Перед кластером примените [elasticsearch-node-sysctl.yaml](elasticsearch-node-sysctl.yaml) — DaemonSet в `kube-system` выставляет `vm.max_map_count` на нодах (привилегированный контейнер с `hostNetwork`/`hostPID`).

```bash
kubectl apply -f elasticsearch-node-sysctl.yaml
kubectl rollout status daemonset/elasticsearch-vm-max-map-count -n kube-system --timeout=5m
```

Манифест кластера — [elasticsearch-eck.yaml](elasticsearch-eck.yaml) (в примере образ **9.3.2**; при необходимости смените `spec.version`, ресурсы и `storageClassName`). При отключённом TLS на HTTP в `podTemplate` задан `readinessProbe` на порт **9200** (иначе проверка ECK ориентируется на **8080** и под остаётся `0/1` Ready).

```bash
kubectl create namespace elasticsearch
kubectl apply -f elasticsearch-eck.yaml
```

Проверка готовности:

```bash
kubectl -n elasticsearch get elasticsearch.elasticsearch.k8s.elastic.co sentry-nodestore -w
kubectl -n elasticsearch get pods,svc
```

ECK создаёт HTTP-сервис **`<имя-ресурса>-es-http`**. Для `metadata.name: sentry-nodestore` это `sentry-nodestore-es-http`. Полный DNS из подов в `sentry`:

`sentry-nodestore-es-http.elasticsearch.svc.cluster.local:9200`

В манифесте отключены TLS на HTTP и встроенная security Elasticsearch (**в продакшене** включите TLS и учётные записи по [документации Elastic](https://www.elastic.co/guide/en/elasticsearch/reference/current/configuring-security.html)).

**1.3. Сборка и публикация образа Sentry**

```bash
docker build -f Dockerfile.sentry-nodestore -t <registry>/sentry-nodestore:26.2.1 .
docker push <registry>/sentry-nodestore:26.2.1
```

В values при установке Sentry:

```yaml
images:
  sentry:
    repository: <registry>/sentry-nodestore
    tag: "26.2.1"
```

**1.4. Интеграция nodestore в Sentry**

В `config.sentryConfPy` (или через [values_sentry.yaml.tpl](values_sentry.yaml.tpl) → переменная `nodestore_elasticsearch_sentry_conf_py`) задайте клиент и приложение Django, например для HTTP без TLS (как в манифесте ECK выше):

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

Установка или обновление релиза с nodestore (отдельный файл values с образом и `config.sentryConfPy`):

```bash
helm upgrade --install sentry sentry/sentry --version 29.5.1 -n sentry \
  -f values-sentry-minimal.yaml -f values-sentry-nodestore.yaml --timeout=900s
```

(`values-sentry-nodestore.yaml` — ваш файл поверх [values-sentry-minimal.yaml](values-sentry-minimal.yaml).)

После первого подключения к Elasticsearch инициализируйте шаблон индекса nodestore:

```bash
kubectl -n sentry exec -it deploy/sentry-web -- sentry upgrade --with-nodestore
```

Пакет `sentry-nodestore-elastic` относится к **sentry-web** и воркерам на том же образе. **Relay** и **taskbroker** отдельно не настраиваются. Для **Snuba** при необходимости см. [Dockerfile.snuba-nodestore](Dockerfile.snuba-nodestore).

**1.5. TLS и версии**

- Для HTTPS и аутентификации настройте Elasticsearch по [документации Elastic](https://www.elastic.co/guide/en/elasticsearch/reference/current/configuring-security.html) и используйте `basic_auth` / `ssl_assert_fingerprint` в клиенте Python — см. [PyPI sentry-nodestore-elastic](https://pypi.org/project/sentry-nodestore-elastic/).
- Версия образа Sentry должна совпадать с `appVersion` чарта Sentry (`helm show chart sentry/sentry --version <ver>`).
- Кластер **9.x** и образ с **elasticsearch-py 9.x** согласованы с [elasticsearch-eck.yaml](elasticsearch-eck.yaml) и `Dockerfile.sentry-nodestore`.

**1.6. Удаление**

```bash
kubectl delete elasticsearch sentry-nodestore -n elasticsearch
kubectl delete namespace elasticsearch
```

Оператор ECK, если больше не нужен: удалите ресурсы в `elastic-system` (например `kubectl delete namespace elastic-system`) и при отсутствии других ресурсов ECK в кластере — CRD по [документации Elastic](https://www.elastic.co/docs/deploy-manage/uninstall/uninstall-elastic-cloud-on-kubernetes).

### 2. ClickHouse


**2.1. Установка Altinity ClickHouse Operator**:

```bash
helm repo add altinity https://helm.altinity.com
helm repo update
helm upgrade --install clickhouse-operator altinity/altinity-clickhouse-operator \
  --version 0.26.2 \
  --namespace clickhouse-operator \
  --create-namespace \
  --wait
```

Оператор через ClickHouseOperatorConfiguration будет наблюдать за namespace `clickhouse`


```bash
kubectl apply -n clickhouse-operator -f clickhouse-operator-config.yaml 
```

Перезапуск оператора, чтобы подхватить ClickHouseOperatorConfiguration.
Подробнее в issue https://github.com/Altinity/clickhouse-operator/issues/1930.

```bash
kubectl rollout status deployment/clickhouse-operator-altinity-clickhouse-operator -n clickhouse-operator --timeout=1m
```

Имя deployment задаёт Helm (release `clickhouse-operator` + chart `altinity-clickhouse-operator`). При другом `--name` релиза смотрите: `kubectl get deploy -n clickhouse-operator`.

**2.2. Создание ClickHouse**:

```bash
kubectl apply -f clickhouse.yaml
```

### 3. Репозиторий Sentry

Репозиторий и namespace уже созданы в шаге 0. При необходимости повторите:

```bash
kubectl create namespace sentry
helm repo add sentry https://sentry-kubernetes.github.io/charts
helm repo update
```

### 4. Установка Sentry

Пример только с [values-sentry-minimal.yaml](values-sentry-minimal.yaml) (без nodestore в Elasticsearch):

```bash
helm upgrade --install sentry sentry/sentry --version 29.5.1 -n sentry \
  -f values-sentry-minimal.yaml --timeout=900s
```

С **Elasticsearch** для nodestore следуйте **§ 1.3–1.4** выше и передайте дополнительный `-f` с `images.sentry` и `config.sentryConfPy`.

### 5. Проверка подов и логов

В конце установки Sentry убедитесь, что все Job завершились (статус `Completed`). Пока Job ещё запущены, поды инициализации могут быть в статусе `Running`, а helm может ждать готовности.

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
