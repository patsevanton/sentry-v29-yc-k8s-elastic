# Демо-приложения для отправки событий в Sentry

Два HTTP-сервиса (Python / FastAPI и Node.js / Express) с одинаковыми маршрутами для проверки self-hosted Sentry: исключения, сообщения, транзакции, breadcrumbs, контекст.

## Маршруты

| Путь | Описание |
|------|----------|
| `GET /health` | Проверка готовности (без DSN) |
| `GET /demo/exception` | Необработанное исключение |
| `GET /demo/capture-exception` | `capture_exception` |
| `GET /demo/message` | `capture_message` (info + warning) |
| `GET /demo/transaction` | Spans / performance |
| `GET /demo/breadcrumb` | Breadcrumb, затем ошибка |
| `GET /demo/context` | Теги, user, context + message |

Без `SENTRY_DSN` маршруты `/demo/*` отвечают **503**; `/health` всегда **200**.

## DSN

1. В UI Sentry создайте проект (например Python и/или Node — для демо подойдёт любой; SDK отправляет по одному DSN).
2. Скопируйте DSN (**Settings → Client Keys**). Для подов в кластере DSN должен указывать на **доступный из кластера** хост Sentry (часто тот же URL, что в браузере, или внутренний Ingress). Если события не доходят, проверьте DNS и сетевую связность до Relay/Ingress.

## Сборка образов

Из корня репозитория:

```bash
docker build -t sentry-demo-python:latest -f demo/python/Dockerfile demo/python
docker build -t sentry-demo-node:latest -f demo/node/Dockerfile demo/node
```

Для облачного кластера замените тег на свой реестр и выполните `docker push`:

```bash
docker tag sentry-demo-python:latest ghcr.io/<org>/sentry-demo-python:v1
docker push ghcr.io/<org>/sentry-demo-python:v1
```

В манифестах [`demo/k8s/deployment-python.yaml`](k8s/deployment-python.yaml) и [`demo/k8s/deployment-node.yaml`](k8s/deployment-node.yaml) укажите то же значение поля `image:`.

## Secret с DSN

```bash
kubectl apply -f demo/k8s/namespace.yaml
kubectl create secret generic sentry-dsn -n demo-sentry \
  --from-literal=dsn='https://<public_key>@<host>/<project_id>'
```

Манифест Secret с плейсхолдером: [`demo/k8s/secret-sentry-dsn.yaml`](k8s/secret-sentry-dsn.yaml).

## Развёртывание в Kubernetes

```bash
kubectl apply -f demo/k8s/namespace.yaml
# Secret с DSN (один из вариантов):
kubectl create secret generic sentry-dsn -n demo-sentry --from-literal=dsn='https://...'
# либо подставить dsn в k8s/secret-sentry-dsn.yaml и:
# kubectl apply -f demo/k8s/secret-sentry-dsn.yaml

kubectl apply -f demo/k8s/deployment-python.yaml
kubectl apply -f demo/k8s/deployment-node.yaml
kubectl apply -f demo/k8s/service.yaml
```

Если образы только локально (kind/minikube/k3d), загрузите их в кластер (`kind load docker-image ...`, `minikube image load ...`) или используйте `imagePullPolicy: Never` и те же теги.

## Проверка (port-forward и curl)

```bash
kubectl -n demo-sentry port-forward svc/sentry-demo-python 18080:8080 &
kubectl -n demo-sentry port-forward svc/sentry-demo-node 18081:8080 &
curl -s http://127.0.0.1:18080/health
curl -s http://127.0.0.1:18081/health
curl -s "http://127.0.0.1:18080/demo/message"
curl -s "http://127.0.0.1:18080/demo/exception"
```

Откройте проект в Sentry и убедитесь, что появились issues и (при включённом performance) транзакции.
