# TODO

## Redis: отключить replicas или включить Sentinel

**Статус:** Требует исследования

**Проблема:** Bitnami Redis chart по умолчанию создаёт master + replicas, но Sentry подключается только к `sentry-sentry-redis-master`. Replicas-под не используется ни одним компонентом Sentry и просто потребляет ресурсы.

**Варианты решения:**

1. **Отключить replicas** — добавить в `values_sentry.yaml.tpl`:
   ```yaml
   redis:
     replica:
       replicaCount: 0
   ```
   Или переключить на `architecture: standalone`.

2. **Включить Sentinel** — для автоматического failover:
   ```yaml
   redis:
     sentinel:
       enabled: true
   ```
   Потребует также обновить конфигурацию `redis.clusters` в `sentry.conf.py` (ConfigMap) для подключения через Sentinel.

3. **Использовать Yandex Managed Redis** — вынести Redis во внешний сервис с SLA и репликацией.

**Файлы для изменения:**
- `values_sentry.yaml.tpl` (строка 44–59) — настройки Redis
- `sentry.conf.py` в ConfigMap `sentry-sentry` — подключение к Redis (только если выбран вариант с Sentinel)
