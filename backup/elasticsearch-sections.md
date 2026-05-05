# Elasticsearch (nodestore) и оператор ECK — перенесено из README.md

> **Статус:** компоненты перенесены в `backup/`. Nodestore работает на стандартном бэкенде Sentry (Bigtable/Redis). Все файлы манифестов сохранены в `backup/elasticsearch.yaml` и `backup/elasticsearch-sections/` для возможного восстановления.

## Историческая инструкция по ECK и Elasticsearch

Nodestore хранит «сырые» узлы событий; здесь используется [sentry-nodestore-elastic](https://pypi.org/project/sentry-nodestore-elastic/) и кластер **Elasticsearch 9.x** через [ECK](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html). Чарт Sentry не ставит `sentry-nodestore-elastic` сам, поэтому нужен **кастомный образ** на базе `ghcr.io/getsentry/sentry` ([реестр](https://github.com/getsentry/sentry/pkgs/container/sentry) — см. `Dockerfile.sentry-nodestore`. На PyPI у пакета ограничение `elasticsearch<9` (Python-клиент); для кластера **9.x** клиент **9.x** в образе ставится отдельно (комментарии в `Dockerfile.sentry-nodestore`).

### 2.1. Оператор Elasticsearch (ECK)

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

### 2.2. Кластер Elasticsearch 9.x

Манифест кластера — `backup/elasticsearch.yaml`.

```bash
kubectl create namespace elasticsearch
kubectl apply -f backup/elasticsearch.yaml
```

Проверка готовности:

```bash
kubectl -n elasticsearch get elasticsearch.elasticsearch.k8s.elastic.co sentry-nodestore
kubectl -n elasticsearch get pods,svc
```

ECK создаёт HTTP-сервис `**<имя-ресурса>-es-http**`. Для `metadata.name: sentry-nodestore` это `sentry-nodestore-es-http`. Полный DNS из подов в `sentry`:

`sentry-nodestore-es-http.elasticsearch.svc.cluster.local:9200`

В манифесте отключены TLS на HTTP и встроенная security Elasticsearch: это упрощает минимальный сценарий — nodestore в Sentry подключается по обычному `http://` без выдачи сертификатов, доверия к CA и без логина и пароля в `sentryConfPy`; трафик к API Elasticsearch остаётся внутри сети кластера.

## См. также

- `backup/elasticsearch.yaml` — манифест кластера Elasticsearch
- `backup/nodestore-sections.md` — секции из values_sentry.yaml.tpl и templatefile.tf для восстановления nodestore
- `backup/Dockerfile.sentry-nodestore` — кастомный Docker-образ Sentry с sentry-nodestore-elastic
- `backup/Dockerfile.snuba-nodestore` — кастомный Docker-образ Snuba
