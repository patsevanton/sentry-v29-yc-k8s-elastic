# Настройка кэширования Sentry через Memcached

## Исходный код

```python
memcached = env("SENTRY_MEMCACHED_HOST") or (env("MEMCACHED_PORT_11211_TCP_ADDR") and "memcached")
if memcached:
    memcached_port = env("SENTRY_MEMCACHED_PORT") or "11211"
    CACHES = {
        "default": {
            "BACKEND": "sentry.cache.backends.reconnectingmemcache.ReconnectingMemcache",
            "LOCATION": [memcached + ":" + memcached_port],
            "TIMEOUT": 3600,
            "OPTIONS": {"ignore_exc": True, "reconnect_age": 300},
        }
    }
```

## Назначение

Код настраивает кэширование Sentry через **Memcached** — систему распределённого кэширования в памяти.

## Логика работы

### 1. Определение хоста

| Приоритет | Переменная окружения | Поведение |
|-----------|----------------------|-----------|
| 1 | `SENTRY_MEMCACHED_HOST` | Используется напрямую, если задана |
| 2 | `MEMCACHED_PORT_11211_TCP_ADDR` | Автоматические Docker-ссылки (legacy). Если существует — используется имя контейнера `memcached` |

### 2. Определение порта

- `SENTRY_MEMCACHED_PORT` — если задана
- По умолчанию — `11211` (стандартный порт Memcached)

### 3. Конфигурация Django CACHES

| Параметр | Значение | Описание |
|----------|----------|----------|
| `BACKEND` | `ReconnectingMemcache` | Кастомный бэкенд Sentry с автопереподключением |
| `LOCATION` | `host:port` | Адрес сервера Memcached |
| `TIMEOUT` | `3600` | Время жизни кэша — 1 час |
| `ignore_exc` | `True` | Игнорировать ошибки Memcached (приложение не падает при недоступности кэша) |
| `reconnect_age` | `300` | Переподключаться каждые 5 минут |

## Зачем нужно

- **Ускорение работы** — кэшируются частые запросы: конфигурация, сессии, результаты дорогих вычислений
- **Устойчивость к сбоям** — бэкенд `ReconnectingMemcache` автоматически восстанавливает соединение при обрыве
- **Безопасный fallback** — при недоступности Memcached приложение продолжает работать (благодаря `ignore_exc: True`)
