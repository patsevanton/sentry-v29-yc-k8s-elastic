# TODO

## Добавить в ClickHouseInstallation

- [ ] Добавить встроенный Prometheus-endpoint ClickHouse (`settings` в `spec.configuration`):
  ```yaml
  settings:
    prometheus/port: "9363"
    prometheus/metrics: "true"
    prometheus/events: "true"
    prometheus/asynchronous_metrics: "true"
  ```
- [ ] Добавить `startup_scripts` для автоматического создания БД `sentry` при запуске ClickHouse (`files` в `spec.configuration`):
  ```yaml
  files:
    config.d/init-sentry.xml: |
      <clickhouse>
        <startup_scripts>
          <script>
            <query>CREATE DATABASE IF NOT EXISTS sentry</query>
          </script>
        </startup_scripts>
      </clickhouse>
  ```
  Без этого при каждом пересоздании пода ClickHouse нужно создавать БД `sentry` вручную:
  ```bash
  kubectl -n clickhouse exec chi-sentry-clickhouse-sentry-cluster-0-0-0 -- \
    clickhouse-client -q "CREATE DATABASE IF NOT EXISTS sentry"
  ```
- [ ] После включения Prometheus-endpoint применить VMServiceScrape `k8s/vmscrape-clickhouse-server.yaml` (см. §7.2 README) и импортировать дашборд [ClickHouse_Queries_dashboard.json](https://github.com/Altinity/clickhouse-operator/blob/master/grafana-dashboard/ClickHouse_Queries_dashboard.json).

## Проверить в будущем

- [ ] Зафиксировано по исследованию Kafka: `externalKafka.provisioning.replicationFactor=3` в `values_sentry.yaml` влияет только на provisioning-job Helm; при включенном `auto_create_topics_enable=true` авто-созданные брокером топики могут оставаться с RF=1, поэтому в YC у них «Высокая доступность: отсутствует».

- проверить CACHES в sentry.conf.py. Подробнее в https://github.com/getsentry/sentry/blob/master/self-hosted/sentry.conf.py#L113 и в файле memcached-config-summary.md

## Идеи для снижения расходов и повышения производительности

- [ ] Autoscaling workload-ов: HPA/VPA, корректные requests/limits; для pod-ов с Kafka — KEDA (триггер по lag/глубине очереди и т.п.).
- [ ] Включить TTL/политику очистки старых событий, сэмплинг и фильтрацию шумных логов/трейсов.
- [ ] Тонко настроить Kafka/consumer group (batch size, parallelism), чтобы снизить lag и пиковые затраты.
- [ ] Пересмотреть размер и тип дисков (IOPS/throughput), чтобы не переплачивать за избыточные ресурсы.
- [ ] Вынести тяжёлые аналитические запросы в отдельный контур или отдельные реплики ClickHouse.
- [ ] Включить кэширование частых запросов (Redis/HTTP cache) и уменьшить нагрузку на БД.
- [ ] Настроить регулярные нагрузочные тесты и performance budget (SLO + алерты на деградацию).
- [ ] Подготовить нагрузочное тестирование из большого количества приложений (`app`), которые массово отправляют `exception` в Sentry, и зафиксировать метрики по ingest, lag и стабильности.
- [ ] Проверить корректность очистки/retention для ClickHouse, S3, Symbolicator и других мест, где накапливаются данные.
- [ ] Добавить failover/chaos-сценарии для ingest-контура (недоступность Kafka/ClickHouse/S3) и проверить, что система восстанавливается без потери данных сверх допустимого SLO.
