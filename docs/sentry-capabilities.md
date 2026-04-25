# Возможности Sentry v30: что реализовано в проекте

> Этот документ — сводная таблица всех ключевых возможностей Sentry SDK и платформы (версия ~v30.1.0) с указанием, что уже демонстрируется в демо-приложениях (`demo/`, `examples/`), а что — нет.
> Ориентирован на Python и Node.js backend SDK. Frontend-фичи (Session Replay, Web Vitals) отмечены отдельно.

---

## 1. Error Monitoring (Мониторинг ошибок)

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| Необработанные исключения (unhandled) | ✅ | ✅ | ✅ | `/demo/exception` — бросаем RuntimeError/Error, интеграция перехватывает |
| Ручной захват ошибок (`capture_exception`) | ✅ | ✅ | ✅ | `/demo/capture-exception` — та же ошибка, но показывает, что можно явно вызвать SDK |
| Последнее событие (`last_event_id`) | ✅ | ✅ | ❌ | Используется для связывания ошибки с User Feedback (см. раздел 8) |
| Группировка ошибок (Fingerprinting) | ✅ | ✅ | ❌ | `set_fingerprint()` позволяет объединять разные события в один Issue или наоборот |
| Фильтрация событий (`before_send`) | ✅ | ✅ | ❌ | Callback перед отправкой — удаление PII, санация данных, отбрасывание спама |
| Приоритет событий (`level`) | ✅ | ✅ | ❌ | `capture_event(level="fatal")` влияет на urgency и алерты |
| Исключения с причиной (`__cause__`, `__context__`) | ✅ | ✅ | ❌ | Цепочки исключений (Python: `raise ... from e`) — Sentry показывает всю цепочку в UI |

---

## 2. Performance / Distributed Tracing

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| Автотрассировка HTTP-сервер | ✅ | ✅ | ✅ | FastAPI/Express интеграции создают root-транзакцию на каждый HTTP-запрос |
| Ручные спаны (`start_span`) | ✅ | ✅ | ✅ | `/demo/transaction` — базовый пример `outer` → `inner` |
| Вложенные спаны | ✅ | ✅ | ✅ | Spans образуют дерево; `inner` — child `outer` |
| Декоратор `@sentry_sdk.trace` / `@Sentry.trace` | ✅ | ✅ | ❌ | Автоматическая обёртка функции в спан; удобнее, чем `with start_span()` |
| HTTP Client спаны (requests, fetch, axios) | ✅ | ✅ | ❌ | `http.client` спан создаётся автоматически при вызове внешнего API |
| База данных (psycopg, asyncpg, prisma) | ✅ | ✅ | ❌ | `db.query` спан — время SQL-запроса, запрос целиком, строка затронутых rows |
| Кэш (Redis, Memcached) | ✅ | ✅ | ❌ | `cache.get` / `cache.set` спаны с hit/miss статусом |
| Очереди (Kafka, Celery, RabbitMQ) | ✅ | ✅ | ❌ | `queue.publish` / `queue.process` спаны; важно для проекта с Yandex Managed Kafka |
| Distributed Tracing (`sentry-trace`, `baggage`) | ✅ | ✅ | ❌ | Проброс trace-контекста через HTTP-заголовки между сервисами; ключевая фича микросервисов |
| `update_current_span()` | ✅ | ❌ | ❌ | Python: изменить op/name/attributes активного спана «на лету» |
| `functions_to_trace` в `init()` | ✅ | ❌ | ❌ | Python: централизованный список функций для трассировки без изменения кода |

---

## 3. Logs (Структурированные логи) — Новое в SDK v2.35+

> Sentry принимает структурированные логи через `sentry_logger` / `Sentry.logger`. Логи связываются с ошибками и трассировками по `trace_id`.

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| `sentry_logger.info()` / `Sentry.logger.info()` | ✅ | ✅ | ❌ | Требует `enable_logs=True` в `init()` |
| `sentry_logger.error()` с атрибутами | ✅ | ✅ | ❌ | Шаблоны `{user_id}` + `attributes={}` — поиск по полям в Logs UI |
| `before_send_log` фильтрация | ✅ | ✅ | ❌ | Отбрасывание спам-логов, санация |
| Интеграция `logging` (Python stdlib) | ✅ | — | ❌ | Перехват `logging.error` → Sentry; можно оставить привычный `logging.*` |
| Интеграция `loguru` | ✅ | — | ❌ | Аналогично, для проектов на `loguru` |
| `Sentry.logger.fatal()` | ✅ | ✅ | ❌ | Fatal-логи создают Issue автоматически |

---

## 4. Profiling (Профилирование)

> Профилирование показывает flamegraph на уровне функций, а не только уровня спанов. Работает параллельно с tracing.

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| Continuous Profiling (`profile_lifecycle="trace"`) | ✅ | ✅ | ❌ | Профайлер работает пока есть активный спан; автоматический старт/стоп |
| Manual Profiling (`start_profiler`/`stop_profiler`) | ✅ | ✅ | ❌ | Полный контроль: явный старт и стоп сессии профилирования |
| Transaction-based Profiling | ✅ | ✅ | ❌ | Устаревший режим (до SDK 2.24); работает только в рамках одной транзакции |
| `profile_session_sample_rate` | ✅ | ✅ | ❌ | Семплирование профилей: 1.0 = все, 0.1 = 10% сервисов |
| Node Profiling Integration (`@sentry/profiling-node`) | — | ✅ | ❌ | Отдельный npm-пакет; native addon для C++ profiling |

---

## 5. Metrics (Метрики) — Новое в SDK 2.44+

> Метрики отправляются напрямую в Sentry (counter, gauge, distribution). Можно искать и строить дашборды. Не требует отдельного Prometheus/Graphite.

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| Counter (`metrics.count`) | ✅ | ✅ | ❌ | Счётчик событий: `button_click`, `http_request` |
| Gauge (`metrics.gauge`) | ✅ | ✅ | ❌ | Текущее значение: `queue.length`, `memory.usage` |
| Distribution (`metrics.distribution`) | ✅ | ✅ | ❌ | Распределение значений: `page_load_ms`, `db_query_ms` (p90, avg, min, max) |
| `before_send_metric` | ✅ | ✅ | ❌ | Фильтрация/модификация метрик перед отправкой |
| Авто-атрибуты (environment, release, server) | ✅ | ✅ | ❌ | SDK автоматически добавляет контекст к каждой метрике |

---

## 6. Crons (Мониторинг Cron-задач)

> Отслеживает запуск, runtime, missed runs и фейлы фоновых задач. Создаёт Issue при проблемах.

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| Декоратор `@monitor()` | ✅ | ✅ | ❌ | Обор��чивает функцию: auto check-in OK / ERROR |
| Контекстный менеджер `with monitor()` | ✅ | ✅ | ❌ | Тоже самое, но для блоков кода |
| Ручные check-ins (`capture_checkin`) | ✅ | ✅ | ❌ | Два вызова: IN_PROGRESS → OK; полный контроль |
| Программное создание монитора (`monitor_config`) | ✅ | ✅ | ❌ | Создание/обновление монитора через SDK без UI |
| Интеграция с Celery Beat | ✅ | — | ❌ | Auto-discovery периодических задач Celery |

---

## 7. Enriching Events (Обогащение событий)

> Добавление контекста к ошибкам и транзакциям для быстрого дебага.

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| Breadcrumbs (`add_breadcrumb`) | ✅ | ✅ | ✅ | `/demo/breadcrumb` — хлебные крошки до ошибки |
| Tags (`set_tag` / `set_tags`) | ✅ | ✅ | ✅ | `/demo/context` — индексируемые поля для фильтров и группировок |
| User (`set_user`) | ✅ | ✅ | ✅ | `/demo/context` — ID, email, username; связывает события с пользователем |
| Extra Context (`set_context`) | ✅ | ✅ | ✅ | `/demo/context` — произвольные JSON-структуры; не индексируются, но видны в UI |
| Attachments (файлы к событиям) | ✅ | ✅ | ❌ | Прикрепление логов, JSON, скриншотов к ошибке (до нескольких МБ) |
| Event Processors | ✅ | ✅ | ❌ | Глобальные и scope-level обработчики событий перед отправкой |
| Scopes (`with_scope`, `push_scope`) | ✅ | ✅ | ❌ | Изоляция данных между запросами; важно для async/threaded окружений |
| Transaction Name | ✅ | ✅ | ❌ | Переопределение имени транзакции для группировки в Performance UI |
| Request Isolation | ✅ | ✅ | ❌ | Гарантия, что `set_user`/`set_tag` одного запроса не «утекают» в другой |

---

## 8. User Feedback (Обратная связь от пользователей)

> Сбор обратной связи при ошибке (имя, email, описание). Соединяется с конкретным событием по `event_id`.

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| Crash-Report Modal (500.html + JS SDK) | ✅ | — | ❌ | Встраиваемый JS-виджет на странице ошибки; требует `last_event_id` из backend |
| User Feedback API | ⚠️ | ⚠️ | ❌ | Основной SDK — браузерный; backend SDK помогает передать `event_id` |
| Feedback Widget | — | — | ❌ | Только браузер; плавающая кнопка «Отправить фидбек» |

---

## 9. AI Agent Monitoring (Мониторинг ИИ-агентов) — Новое

> Отслеживание LLM-вызовов: токены, latency, tool execution, error rate. Интеграция с OpenTelemetry-семантикой.

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| OpenAI интеграция | ⚠️ | ✅ | ❌ | Node: `openAIIntegration()` — автоматические спаны |
| Anthropic интеграция | — | ✅ | ❌ | — |
| Vercel AI SDK интеграция | — | ✅ | ❌ | — |
| LangChain / LangGraph интеграция | ✅ | ✅ | ❌ | — |
| Ручные AI-спаны (`gen_ai.request`, `gen_ai.invoke_agent`) | ✅ | ✅ | ❌ | Ручная инструментация любого LLM-клиента |
| `setConversationId()` | — | ✅ | ❌ | Node: связывает все AI-спаны одного диалога |
| MCP Server Monitoring | — | ✅ | ❌ | Model Context Protocol: tool executions, prompt retrievals |
| Span Templates (`SPANTEMPLATE.AI_AGENT`) | ✅ | — | ❌ | Python: `@sentry_sdk.trace(template=SPANTEMPLATE.AI_AGENT)` |

---

## 10. Feature Flags (Фичефлаги)

> Трекинг значений фичефлагов на момент ошибки. Помогает понять, включён ли был эксперимент.

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| LaunchDarkly интеграция | ✅ | — | ❌ | Python: `sentry_sdk.integrations.launchdarkly` |
| OpenFeature интеграция | ✅ | — | ❌ | Универсальный стандарт; работает с любыми провайдерами |
| Statsig интеграция | ✅ | ✅ | ❌ | — |
| Unleash интеграция | ✅ | — | ❌ | — |
| Generic API (`add_feature_flag`) | ✅ | — | ❌ | `from sentry_sdk.feature_flags import add_feature_flag` — для любого провайдера |
| Change Tracking Webhooks | ✅ | ✅ | ❌ | Webhook от провайдера → Sentry: аудит изменений флагов |

---

## 11. Интеграции и Auto-Instrumentation

> Автоматическая инструментация популярных фреймворков и библиотек. Многие включаются просто установкой пакета.

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| FastAPI / Starlette | ✅ | — | ✅ | `FastApiIntegration`, `StarletteIntegration` |
| Express | — | ✅ | ✅ | `setupExpressErrorHandler` |
| Django / Flask | ✅ | — | ❌ | — |
| SQLAlchemy / Django ORM | ✅ | — | ❌ | Авто-спаны на SQL-запросы |
| Prisma / Sequelize | — | ✅ | ❌ | — |
| Redis | ✅ | ✅ | ❌ | — |
| Celery | ✅ | — | ❌ | Worker + Beat (Crons) |
| Kafka (confluent-kafka) | ✅ | — | ❌ | Producer / Consumer спаны |
| Asyncio | ✅ | — | ❌ | Специальная asyncio-интеграция для корректных scopes |
| GraphQL | ✅ | ✅ | ❌ | Спаны на resolver-ы |
| gRPC | ✅ | ✅ | ❌ | Спаны на RPC-вызовы |
| AWS Lambda | ✅ | ✅ | ❌ | — |
| Browser / Frontend SDK | — | — | ❌ | В проекте только backend; для Session Replay нужен React/Vue/JS SDK |

---

## 12. Security & Data Management

> Управление чувствительными данными и семплированием.

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| `send_default_pii` / `sendDefaultPii` | ✅ | ✅ | ❌ | Отправка IP, user agent, cookies (GDPR-риск; включать осознанно) |
| `before_send` для санации данных | ✅ | ✅ | ❌ | Удаление паролей, токенов из событий перед отправкой |
| Security Policy Reports (CSP, HPKP) | ✅ | ✅ | ❌ | Endpoint для получения CSP-отчётов от браузера |
| In-App Frames / System frames | ✅ | ✅ | ⚠️ | Работает автоматически; frame, принадлежащий вашему коду, vs библиотечный |
| Data Scrubbing (на сервере Sentry) | ✅ | ✅ | ⚠️ | Настраивается в UI: Advanced Data Scrubbing rules |
| Sampling (`traces_sample_rate`) | ✅ | ✅ | ✅ | Установлен `1.0` (100% трейсов) — для демо; в production рекомендуется 0.1–0.3 |
| Dynamic Sampling (`traces_sampler`) | ✅ | ✅ | ❌ | Функция, возвращающая решение о семплировании на основе контекста |

---

## 13. Product / Platform (Инфраструктурные возможности)

| Возможность | Python | Node | Реализовано | Комментарий |
|-------------|--------|------|-------------|-------------|
| Source Maps (Node) | — | ✅ | ✅ | `examples/sourcemap-upload` — загрузка карт в релиз |
| Debug Symbols / Native (C/C++) | ✅ | — | ✅ | `examples/sentry-native-debug-sample` — ELF + DWARF |
| Releases (`release` в init) | ✅ | ✅ | ❌ | Связывает события с версией кода; нужен для Source Maps и Suspect Commits |
| Environments (`environment` в init) | ✅ | ✅ | ❌ | `production`/`staging` — фильтрация в UI |
| Dist / Server Name | ✅ | ✅ | ❌ | Уточнение платформы (iOS dist, server hostname) |
| Session Replay | — | — | ❌ | Только браузер: запись действий пользователя перед ошибкой |
| Performance Insights (Web Vitals) | — | — | ❌ | Только браузер: LCP, FID, CLS |
| Codecov Integration | — | — | ❌ | SaaS-интеграция: покрытие кода рядом со стектрейсом |
| SCM Integration (GitHub/GitLab) | — | — | ⚠️ | Настраивается в UI Sentry: Suspect Commits, Resolve via PR |

---

## Итоговая статистика

| Категория | Реализовано | Всего | Процент |
|-----------|-------------|-------|---------|
| Error Monitoring | 2 | 7 | ~29% |
| Performance / Tracing | 3 | 10 | ~30% |
| Logs | 0 | 5 | 0% |
| Profiling | 0 | 4 | 0% |
| Metrics | 0 | 4 | 0% |
| Crons | 0 | 4 | 0% |
| Enriching Events | 4 | 8 | 50% |
| User Feedback | 0 | 3 | 0% |
| AI Agent Monitoring | 0 | 8 | 0% |
| Feature Flags | 0 | 5 | 0% |
| Интеграции | 2 | 14 | ~14% |
| Security & Data | 1 | 7 | ~14% |
| Product / Platform | 2 | 9 | ~22% |

---

## Рекомендуемый порядок внедрения

1. **Logs + Metrics** — новые фичи v30, максимальная ценность при минимальных усилиях.
2. **Profiling** — включается одной опцией в `init()`; flamegraph сразу показывает hot paths.
3. **Distributed Tracing + HTTP Client спаны** — добавить исходящий HTTP-вызов в демо.
4. **Crons** — если в приложениях есть фоновые задачи (Kubernetes CronJob).
5. **Attachments + Event Processors** — для production-ready качества событий.
6. **AI Agent Monitoring** — если используете LLM (OpenAI, Anthropic, LangChain).
7. **Feature Flags** — если используете LaunchDarkly, Statsig, Unleash или OpenFeature.
8. **Frontend SDK** — для Session Replay, User Feedback и Performance Insights (Web Vitals).
