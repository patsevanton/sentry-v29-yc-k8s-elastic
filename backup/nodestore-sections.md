# Nodestore Sections — backup из values_sentry.yaml.tpl и templatefile.tf
#
# Секции, которые были в values_sentry.yaml.tpl (config.sentryConfPy) и templatefile.tf,
# когда nodestore использовал Elasticsearch 9.x через ECK.
#
# Для восстановления nodestore на Elasticsearch:
# 1. Раскомментируйте секцию в templatefile.tf (переменная elasticsearch_url)
# 2. Вставьте секцию sentryConfPy в values_sentry.yaml.tpl
# 3. Примените: terraform apply
# 4. Примените: helm upgrade --install sentry ...
# 5. Инициализируйте: kubectl -n sentry exec -it deploy/sentry-web -- sentry upgrade --with-nodestore
#
# Требуется:
# - Кастомный Docker-образ Sentry с пакетом sentry-nodestore-elastic
# - ECK Operator v3.3.2 (kubectl apply -f elasticsearch.yaml)
# - Elasticsearch 9.x кластер (sentry-nodestore-es-http.elasticsearch.svc.cluster.local:9200)

## values_sentry.yaml.tpl — секция config.sentryConfPy (заменяет дефолтную)

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

## templatefile.tf — переменная elasticsearch_url (добавить в locals.sentry_config)

    elasticsearch_url = "http://sentry-nodestore-es-http.elasticsearch.svc.cluster.local:9200"
