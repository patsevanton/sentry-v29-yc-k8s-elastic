# Sentry v30.1.0 в Yandex Cloud на Kubernetes

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
- **DNS/IP**: Terraform managed (ip-dns.tf)

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
- ALWAYS проверять `terraform plan` перед `terraform apply`
- ALWAYS делать git checkpoint перед крупными изменениями инфраструктуры
- Одна задача за раз. НЕ делать несколько изменений одновременно
- Если не уверен — СПРОСИ, не угадывай
- При изменении `values_sentry.yaml.tpl` помни: файл генерируется через `templatefile.tf` — проверяй шаблоны переменных
- ClickHouse endpoint содержит только TLS-порт 9440 — проверяй совместимость при изменении настроек

## Working Style

- Сначала ПЛАН, потом код
- Маленькие дифы: один файл → проверка → следующий файл
- Terraform-файлы: проверяй зависимости между ресурсами перед изменением
- Helm values: сверяйся с `values_sentry.yaml.tpl` и документацией чарта
- Kubernetes манифесты: проверяй namespace и зависимости (порядок установки важен)

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
8. Демо-клиенты
