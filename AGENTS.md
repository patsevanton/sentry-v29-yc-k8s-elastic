# Sentry v30.1.0 в Yandex Cloud на Kubernetes

> **Контекстный уровень: Level 1 (Project Details).**
> Перед любым изменением кода или инфраструктуры используй эту карту для навигации.
> Не запускай grep по всему репозиторию вслепую — ориентируйся по разделам ниже.

## Project Map / Карта проекта

| Компонент | Технология | Где управляется | Namespace |
|-----------|-----------|-----------------|-----------|
| Sentry App | Helm chart `sentry/sentry` v30.1.0 | `values_sentry.yaml.tpl`, `templatefile.tf` | `sentry` |
| PostgreSQL | Встроенный в Helm Sentry | `values_sentry.yaml.tpl` | `sentry` |
| ClickHouse | Yandex Managed ClickHouse | Terraform (*.tf) | — (внешний) |
| Kafka | Yandex Managed Kafka | Terraform (*.tf) | — (внешний) |
| Elasticsearch 9.x | ECK Operator | `k8s/eck/` (манифесты) | `sentry` |
| Object Storage (S3) | Yandex Object Storage | Terraform (*.tf) | — (внешний) |
| Autoscaling | KEDA v2.16.1 | Helm `kedacore/keda` | `keda` |
| Monitoring | VictoriaMetrics K8s Stack v0.72.6 | `vmks-values.yaml`, `k8s/` | `vmks` |
| Ingress / DNS | Terraform managed | `ip-dns.tf`, Terraform outputs | — |
| Infra (VPC, K8S) | Terraform | `*.tf` в корне | — |

## Architecture

- **Infrastructure as Code**: Terraform (Yandex Cloud provider)
- **Orchestration**: Kubernetes (Yandex Managed Kubernetes)
- **Application**: Sentry v30.1.0 через Helm-чарт `sentry/sentry`
- **Database**: PostgreSQL (через Helm чарт Sentry)
- **Analytics DB**: ClickHouse (Yandex Managed ClickHouse)
- **Message Broker**: Kafka (Yandex Managed Kafka)
- **Nodestore**: Elasticsearch 9.x через ECK Operator
- **Object Storage**: S3 (Yandex Object Storage) для артефактов
- **Autoscaling**: KEDA (по Kafka lag)
- **Monitoring**: VictoriaMetrics K8s Stack (VMSingle, VMAgent, Grafana)
- **DNS/IP**: Terraform managed (`ip-dns.tf`)

## Key Files / Ключевые файлы

| Файл | Назначение | Когда менять |
|------|-----------|--------------|
| `values_sentry.yaml.tpl` | Шаблон Helm values для Sentry | При изменении конфигурации Sentry, БД, Kafka, ClickHouse, S3 |
| `templatefile.tf` | Генерация `values_sentry.yaml` из шаблона | При добавлении новых переменных в шаблон |
| `values_sentry.yaml` | Сгенерированный Helm values | **НЕ редактировать вручную** — только через Terraform |
| `vmks-values.yaml` | Values для VictoriaMetrics K8s Stack | При изменении мониторинга |
| `ip-dns.tf` | DNS-записи и IP ingress | При изменении сетевой доступности |
| `*.tf` (остальные) | Terraform-ресурсы (VPC, K8S, MDB, S3) | При изменении инфраструктуры |
| `k8s/` | Kubernetes-манифесты (мониторинг, DNS, exporters, ECK) | При изменении объектов вне Helm |
| `dashboard/` | Дашборды Grafana (`sentry-issues-events-overview.json`) | При обновлении визуализаций; импортируется в Grafana после установки VMKS |
| `demo/` | Демо-клиенты (Python, Node.js) | При изменении примеров интеграции |
| `examples/` | Примеры интеграции (native C, source maps) | При добавлении примеров |
| `scripts/` | Вспомогательные скрипты | При изменении служебных скриптов |

## Key Commands

- `terraform init` — инициализация Terraform
- `terraform plan` — план изменений инфраструктуры
- `terraform apply` — применение инфраструктуры
- `terraform output -raw ingress_public_ip` — получить внешний IP ingress
- `terraform output -raw monitoring_api_key` — получить API-ключ мониторинга
- `helm upgrade --install sentry sentry/sentry --version 30.1.0 -n sentry -f values_sentry.yaml --timeout=3600s --create-namespace` — установка/обновление Sentry
- `helm upgrade --install vmks vm/victoria-metrics-k8s-stack --version 0.72.6 -n vmks -f vmks-values.yaml --wait --timeout=15m` — установка VictoriaMetrics
- `helm upgrade --install keda kedacore/keda --version 2.16.1 -n keda --wait --timeout=10m` — установка KEDA
- `kubectl -n sentry get pods` — проверка подов Sentry
- `kubectl -n sentry get jobs` — проверка Job'ов Sentry
- `kubectl -n sentry logs deployment/sentry-web --tail=20` — логи web
- `kubectl -n sentry exec -it deploy/sentry-web -- sentry upgrade --with-nodestore` — инициализация nodestore

## CRITICAL RULES — ОБЯЗАТЕЛЬНО

- NEVER удалять или переписывать существующие Terraform-ресурсы без явного запроса
- NEVER удалять файлы без подтверждения
- NEVER коммитить секреты, токены, пароли (.env, credentials, terraform.tfstate)
- NEVER запрашивать IAM-токен Яндекс.Облака (YC IAM token) у пользователя — это чувствительный секрет с коротким сроком жизни
- ALWAYS проверять `terraform plan` перед `terraform apply`
- ALWAYS делать git checkpoint перед крупными изменениями инфраструктуры
- Одна задача за раз. НЕ делать несколько изменений одновременно
- Если не уверен — СПРОСИ, не угадывай
- При изменении `values_sentry.yaml.tpl` помни: файл генерируется через `templatefile.tf` — проверяй шаблоны переменных
- ClickHouse endpoint содержит только TLS-порт 9440 — проверяй совместимость при изменении настроек

## Working Style / Стиль работы

- Сначала ПЛАН, потом код
- Маленькие дифы: один файл → проверка → следующий файл
- Terraform-файлы: проверяй зависимости между ресурсами перед изменением
- Helm values: сверяйся с `values_sentry.yaml.tpl` и документацией чарта
- Kubernetes манифесты: проверяй namespace и зависимости (порядок установки важен)

## Navigation Guide / Навигация для агента

Перед тем как читать исходный код или запускать поиск:

1. **Определи область изменения** по таблице из раздела **Project Map** выше.
2. **Найди конкретный файл** в разделе **Key Files** — это сократит поиск с десятков файлов до 1-2.
3. **Проверь CRITICAL RULES** — особенно если работаешь с Terraform или шаблонами.
4. **Используй git checkpoint** перед крупными изменениями.
5. Если задача требует изменений в нескольких компонентах — разбей на шаги и согласовывай каждый.

## File Structure

- `*.tf` — Terraform-конфигурация инфраструктуры в корне
- `values_sentry.yaml.tpl` — шаблон Helm values для Sentry (генерируется через Terraform)
- `values_sentry.yaml` — сгенерированный файл (НЕ редактировать вручную)
- `k8s/` — Kubernetes-манифесты (мониторинг, DNS, exporters)
- `demo/` — демо-клиенты Sentry (Python, Node.js)
- `dashboard/` — дашборды Grafana
- `examples/` — примеры интеграции (native C, source maps)
- `scripts/` — вспомогательные скрипты
- `docs/` — дополнительная документация

## Порядок зависимостей при развёртывании

1. Terraform apply (VPC, K8S, ClickHouse, Kafka, S3, DNS)
2. ECK Operator + Elasticsearch 9.x
3. KEDA
4. Helm-репозиторий Sentry + namespace
5. `helm upgrade --install sentry` (с values из Terraform)
6. VictoriaMetrics K8s Stack
7. Мониторинг (Prometheus exporter, VMServiceScrape)
8. Импорт дашборда `dashboard/sentry-issues-events-overview.json` в Grafana
9. Демо-клиенты

## References / Полезные ссылки

- Спецификация метрик Yandex Managed Kafka: https://yandex.cloud/ru/docs/monitoring/metrics-ref/managed-kafka-ref
- Спецификация метрик Yandex Managed ClickHouse: https://yandex.cloud/ru/docs/monitoring/metrics-ref/managed-clickhouse-ref
- Спецификация метрик Yandex Managed Kubernetes: https://yandex.cloud/ru/docs/monitoring/metrics-ref/managed-kubernetes-ref
