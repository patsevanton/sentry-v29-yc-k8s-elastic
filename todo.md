# TODO

## Проверить в будущем

- [ ] Зафиксировано по исследованию Kafka: `externalKafka.provisioning.replicationFactor=3` в `values_sentry.yaml` влияет только на provisioning-job Helm; при включенном `auto_create_topics_enable=true` авто-созданные брокером топики могут оставаться с RF=1, поэтому в YC у них «Высокая доступность: отсутствует».
- [ ] Сделать upstream PR для исправления `TaskBroker` по issue [sentry-kubernetes/charts#2088](https://github.com/sentry-kubernetes/charts/issues/2088): автопроброс `TASKBROKER_KAFKA_*` переменных при `externalKafka.sasl.existingSecret`.
- [ ] Сделать upstream PR в Sentry Helm chart для поддержки `livenessProbe.initialDelaySeconds` на уровне отдельных `taskWorker.workers[]`. Сейчас `initialDelaySeconds` задаётся глобально для всех taskworker'ов через `taskWorker.livenessProbe`, но chart не позволяет переопределить его для конкретного воркера (например, только для `default` и `products`). Нужно добавить поддержку `workers[].livenessProbe` в шаблон `deployment-taskworker.yaml`, чтобы merge'ить per-worker probe настройки поверх глобальных. Подробности: [docs/fix-taskworker-liveness-probe.md](docs/fix-taskworker-liveness-probe.md).
- проверить CACHES в sentry.conf.py

## Идеи для снижения расходов и повышения производительности

- [ ] Autoscaling workload-ов: HPA/VPA, корректные requests/limits; для pod-ов с Kafka — KEDA (триггер по lag/глубине очереди и т.п.).
- [ ] Включить TTL/политику очистки старых событий, сэмплинг и фильтрацию шумных логов/трейсов.
- [ ] Тонко настроить Kafka/consumer group (batch size, parallelism), чтобы снизить lag и пиковые затраты.
- [ ] Пересмотреть размер и тип дисков (IOPS/throughput), чтобы не переплачивать за избыточные ресурсы.
- [ ] Вынести тяжёлые аналитические запросы в отдельный контур или отдельные реплики ClickHouse.
- [ ] Включить кэширование частых запросов (Redis/HTTP cache) и уменьшить нагрузку на БД.
- [ ] Настроить регулярные нагрузочные тесты и performance budget (SLO + алерты на деградацию).
- [ ] Подготовить нагрузочное тестирование из большого количества приложений (`app`), которые массово отправляют `exception` в Sentry, и зафиксировать метрики по ingest, lag и стабильности.
- [ ] Проверить корректность очистки/retention для Elasticsearch, ClickHouse, S3, Symbolicator и других мест, где накапливаются данные.
- [ ] Добавить failover/chaos-сценарии для ingest-контура (недоступность Kafka/ClickHouse/S3) и проверить, что система восстанавливается без потери данных сверх допустимого SLO.
