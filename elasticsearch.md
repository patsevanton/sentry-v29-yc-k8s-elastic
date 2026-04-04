# Установка Elasticsearch для nodestore Sentry

Nodestore хранит «сырые» узлы событий; вместо Cassandra/ScyllaDB здесь используется [sentry-nodestore-elastic](https://pypi.org/project/sentry-nodestore-elastic/) и кластер **Elasticsearch 9.x** (через [ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)).

Чарт Sentry не ставит `sentry-nodestore-elastic` сам (в отличие от варианта nodestore S3), поэтому нужен **кастомный образ** на базе официального образа `ghcr.io/getsentry/sentry` ([GitHub Container Registry](https://github.com/getsentry/sentry/pkgs/container/sentry); образ `getsentry/sentry` на Docker Hub deprecated) — см. `Dockerfile.sentry-nodestore` в репозитории.

Пакет на PyPI ограничивает зависимость `elasticsearch<9` (Python-клиент); для кластера **9.x** в образе клиент **9.x** ставится отдельно (см. комментарии в `Dockerfile.sentry-nodestore`).

## 1. Сборка и публикация образа Sentry

```bash
docker build -f Dockerfile.sentry-nodestore -t <registry>/sentry-nodestore:26.2.1 .
docker push <registry>/sentry-nodestore:26.2.1
```

В `values` при установке Sentry укажите:

```yaml
images:
  sentry:
    repository: <registry>/sentry-nodestore
    tag: "26.2.1"
```

## 2. Helm-репозиторий Elastic (оператор ECK)

```bash
helm repo add elastic https://helm.elastic.co
helm repo update
```

Установите [ECK Operator](https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-install-helm.html):

```bash
helm upgrade --install elastic-operator elastic/eck-operator \
  --version 3.3.2 \
  --namespace elastic-system \
  --create-namespace \
  --wait
```

## 3. Установка Elasticsearch 9.x

Namespace и ресурс из [elasticsearch-eck.yaml](elasticsearch-eck.yaml) (версия образа **9.3.2**, при необходимости смените `spec.version`):

```bash
kubectl create namespace elasticsearch
kubectl apply -f elasticsearch-eck.yaml
```

Дождитесь фазы `green` / готовности подов:

```bash
kubectl -n elasticsearch get elasticsearch.elasticsearch.k8s.elastic.co sentry-nodestore -w
kubectl -n elasticsearch get pods,svc
```

ECK создаёт HTTP-сервис вида **`<имя-ресурса>-es-http`**. Для `metadata.name: sentry-nodestore` это `sentry-nodestore-es-http`. Полный DNS из namespace `sentry`:

`sentry-nodestore-es-http.elasticsearch.svc.cluster.local:9200`

В манифесте отключены TLS на HTTP и встроенная security Elasticsearch (как в прежнем примере с чартом; **в продакшене** включите TLS и учётные записи по [документации Elastic](https://www.elastic.co/guide/en/elasticsearch/reference/current/configuring-security.html)).

### Legacy: чарт `elastic/elasticsearch` (только ES 8.5.x)

Последняя версия чарта [helm.elastic.co](https://helm.elastic.co) — **8.5.1**; новых релизов для стека 9.x нет. Для nodestore на **Elasticsearch 8.x** можно по-прежнему использовать `values-elasticsearch.yaml` и `helm upgrade ... elastic/elasticsearch --version 8.5.1`.

## 4. Конфигурация nodestore в Sentry

В `config.sentryConfPy` (или через `values_sentry.yaml.tpl` → переменная `nodestore_elasticsearch_sentry_conf_py`) задайте клиент Elasticsearch и приложение Django, например для HTTP без TLS (как в манифесте ECK выше):

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

После первого подключения к Elasticsearch выполните инициализацию шаблона индекса (из документации пакета):

```bash
kubectl -n sentry exec -it deploy/sentry-web -- sentry upgrade --with-nodestore
```

## 5. Про TLS и версии

- Для HTTPS и аутентификации настройте Elasticsearch по [документации Elastic](https://www.elastic.co/guide/en/elasticsearch/reference/current/configuring-security.html) и используйте `basic_auth` / `ssl_assert_fingerprint` в клиенте Python — см. пример в [PyPI sentry-nodestore-elastic](https://pypi.org/project/sentry-nodestore-elastic/).
- Версия образа Sentry должна совпадать с `appVersion` чарта Sentry (`helm show chart sentry/sentry --version <ver>`).
- Кластер **9.x** и образ Sentry с **elasticsearch-py 9.x** согласованы с манифестом ECK и текущим `Dockerfile.sentry-nodestore`.

## Удаление

```bash
kubectl delete elasticsearch sentry-nodestore -n elasticsearch
kubectl delete namespace elasticsearch
```

Оператор ECK при необходимости: `helm uninstall elastic-operator -n elastic-system` (если больше нигде не используется).
