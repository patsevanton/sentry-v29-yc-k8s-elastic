# Развёртывание Sentry v29.3.0 в Yandex Cloud на Kubernetes. 

### 0. Подготовка

Создайте необходимые namespace и подключите необходимые helm репозитории

```bash
kubectl create namespace clickhouse
```

### 1. Elasticsearch (nodestore)

Для nodestore в **Elasticsearch** разверните кластер и соберите образ Sentry с пакетом `sentry-nodestore-elastic` — см. [elasticsearch.md](elasticsearch.md) и [Dockerfile.sentry-nodestore](Dockerfile.sentry-nodestore). В `helm upgrade ... sentry` передайте `images.sentry` и `config.sentryConfPy` (или сгенерируйте `values_sentry.yaml` из [values_sentry.yaml.tpl](values_sentry.yaml.tpl)).

### 2. ClickHouse


**2.1. Установка Altinity ClickHouse Operator**:

```bash
helm repo add altinity https://helm.altinity.com
helm repo update
helm upgrade --install clickhouse-operator altinity/altinity-clickhouse-operator \
  --version 0.25.6 \
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
kubectl rollout restart deployment/clickhouse-operator -n clickhouse-operator
```

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
helm upgrade --install sentry sentry/sentry --version 29.3.0 -n sentry \
  -f values-sentry-minimal.yaml --timeout=900s
```

Для nodestore в Elasticsearch добавьте `-f` с вашим `values`, где заданы `images.sentry` (кастомный образ) и `config.sentryConfPy` — см. [elasticsearch.md](elasticsearch.md).

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

Sentry доступен по адресу **http://sentry.apatsev.org.ru** через Traefik (Gateway API HTTPRoute).

Убедитесь, что DNS-запись `sentry.apatsev.org.ru` указывает на внешний IP сервиса Traefik LoadBalancer:

```bash
kubectl -n traefik get svc
```
