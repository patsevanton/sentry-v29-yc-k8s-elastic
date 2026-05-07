# Аутентификация в Yandex Monitoring API

## Как работает аутентификация в этом проекте

Terraform автоматически создаёт:

1. **Сервисный аккаунт** `monitoring-viewer-sa` с ролью `monitoring.viewer` ([monitoring.tf](../monitoring.tf))
2. **API-ключ** этого сервисного аккаунта (`yandex_iam_service_account_api_key`) — используется как bearer-токен
3. **K8S Secret** `yc-monitoring-api-key` в namespace `vmks` — из шаблона [k8s/secret-yc-monitoring-api-key.yaml.tpl](../k8s/secret-yc-monitoring-api-key.yaml.tpl)

VMAgent (из VictoriaMetrics K8s Stack) читает bearer-токен из K8S Secret и делает HTTPS-запрос на `monitoring.api.cloud.yandex.net/monitoring/v2/prometheusMetrics`.

## Почему API-ключ, а не IAM-токен

- **IAM-токен** — максимум 12 часов жизни, требует периодического обновления.
- **API-ключ** — бессрочный, подходит для bearer-аутентификации в Monitoring API.

## Почему не Static Access Key

«Статические ключи доступа» в YC работают только с **S3 API** и **AWS-compatible API**. Для Yandex Monitoring API нужен API-ключ или IAM-токен.

## См. также

- [`monitoring.tf`](../monitoring.tf) — создание сервисного аккаунта, API-ключа и K8S Secret.
- [`k8s/vmstaticscrape-yc-managed-kafka.yaml.tpl`](../k8s/vmstaticscrape-yc-managed-kafka.yaml.tpl) — VMStaticScrape с bearer-аутентификацией.
- [`k8s/secret-yc-monitoring-api-key.yaml.tpl`](../k8s/secret-yc-monitoring-api-key.yaml.tpl) — шаблон K8S Secret.
