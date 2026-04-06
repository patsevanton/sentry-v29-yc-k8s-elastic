# Шаблоны дашбордов

Файл `sentry-issues-events-overview.json` — переносимый шаблон Grafana-дэшборда для метрик Sentry.

## Почему шаблон переносимый

- Использует вход Grafana `${DS_PROMETHEUS}` вместо фиксированного UID datasource.
- Содержит `id: null` и `uid: null`, чтобы избежать конфликтов между системами.
- Переменные `project`, `environment`, `release` по умолчанию выставлены в `All` с `allValue: ".*"`, поэтому панели не пустые при первом открытии.

## Импорт

1. Откройте Grafana: `Dashboards` -> `New` -> `Import`.
2. Загрузите `dashboard/sentry-issues-events-overview.json`.
3. Выберите ваш datasource Prometheus/VictoriaMetrics, когда Grafana запросит `DS_PROMETHEUS`.
4. Сохраните дашборд.
