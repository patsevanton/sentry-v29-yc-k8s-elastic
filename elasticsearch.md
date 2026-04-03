# Установка Elasticsearch для nodestore Sentry

Nodestore хранит «сырые» узлы событий; вместо Cassandra/ScyllaDB здесь используется [sentry-nodestore-elastic](https://pypi.org/project/sentry-nodestore-elastic/) и кластер Elasticsearch 8.x.

Чарт Sentry не ставит `sentry-nodestore-elastic` сам (в отличие от варианта nodestore S3), поэтому нужен **кастомный образ** на базе `getsentry/sentry` — см. `Dockerfile.sentry-nodestore` в репозитории.

## 1. Сборка и публикация образа Sentry

```bash
docker build -f Dockerfile.sentry-nodestore -t <registry>/sentry-nodestore:26.2.0 .
docker push <registry>/sentry-nodestore:26.2.0
```

В `values` при установке Sentry укажите:

```yaml
images:
  sentry:
    repository: <registry>/sentry-nodestore
    tag: "26.2.0"
```

## 2. Helm-репозиторий Elastic

```bash
helm repo add elastic https://helm.elastic.co
helm repo update
```

## 3. Установка Elasticsearch

```bash
kubectl create namespace elasticsearch
helm upgrade --install sentry-nodestore elastic/elasticsearch \
  --version 8.5.1 \
  --namespace elasticsearch \
  -f values-elasticsearch.yaml \
  --wait
```

Проверка:

```bash
kubectl -n elasticsearch get pods,svc
```

Имя сервиса HTTP обычно вида `sentry-nodestore-master` (см. `kubectl -n elasticsearch get svc`). Полный DNS из namespace `sentry`:

`sentry-nodestore-master.elasticsearch.svc.cluster.local:9200`

## 4. Конфигурация nodestore в Sentry

В `config.sentryConfPy` (или через `values_sentry.yaml.tpl` → переменная `nodestore_elasticsearch_sentry_conf_py`) задайте клиент Elasticsearch и приложение Django, например для HTTP без TLS (как в `values-elasticsearch.yaml`):

```python
from elasticsearch import Elasticsearch

es = Elasticsearch(
    ["http://sentry-nodestore-master.elasticsearch.svc.cluster.local:9200"],
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
- Зависимости пакета: `sentry>=26.1,<27` и Elasticsearch 8.x — сочетайте с версией образа `getsentry/sentry` и чарта Sentry (`helm show chart sentry/sentry --version <ver>` → `appVersion`).

## Удаление

```bash
helm uninstall sentry-nodestore -n elasticsearch
kubectl delete namespace elasticsearch
```
