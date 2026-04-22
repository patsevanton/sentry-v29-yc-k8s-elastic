#!/usr/bin/env bash
set -euo pipefail

: "${SENTRY_URL:?missing SENTRY_URL}"
: "${SENTRY_ORG:?missing SENTRY_ORG}"
: "${SENTRY_TEAM:?missing SENTRY_TEAM}"
: "${SENTRY_AUTH_TOKEN:?missing SENTRY_AUTH_TOKEN}"

auth=(-H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" -H "Content-Type: application/json")

ensure_project() {
  local slug="$1"
  local name="$2"
  local platform="$3"

  if curl -sfS "${auth[@]}" \
    "${SENTRY_URL}/api/0/teams/${SENTRY_ORG}/${SENTRY_TEAM}/projects/" \
    | jq -e --arg slug "$slug" '.[] | select(.slug == $slug)' >/dev/null; then
    echo "project exists: ${slug}"
    return
  fi

  curl -sfS "${auth[@]}" -X POST \
    "${SENTRY_URL}/api/0/teams/${SENTRY_ORG}/${SENTRY_TEAM}/projects/" \
    -d "{\"name\":\"${name}\",\"slug\":\"${slug}\",\"platform\":\"${platform}\"}" >/dev/null
  echo "project created: ${slug}"
}

ensure_dsn() {
  local project_slug="$1"

  local dsn
  dsn="$(curl -sfS "${auth[@]}" \
    "${SENTRY_URL}/api/0/projects/${SENTRY_ORG}/${project_slug}/keys/" \
    | jq -r 'first(.[]?.dsn.public // empty)')"

  if [[ -z "${dsn}" ]]; then
    dsn="$(curl -sfS "${auth[@]}" -X POST \
      "${SENTRY_URL}/api/0/projects/${SENTRY_ORG}/${project_slug}/keys/" \
      -d '{"name":"auto-generated"}' \
      | jq -r '.dsn.public')"
  fi

  printf '%s\n' "${dsn}"
}

# Projects used in demo
ensure_project "demo-node" "Demo Node" "node"
ensure_project "demo-python" "Demo Python" "python"

# Projects used in examples
ensure_project "native" "Native Debug Sample" "c"
ensure_project "sourcemap-upload" "Sourcemap Upload" "javascript"

NODE_DSN="$(ensure_dsn "demo-node")"
PYTHON_DSN="$(ensure_dsn "demo-python")"

kubectl apply -f demo/k8s/namespace.yaml
kubectl -n demo-sentry create secret generic sentry-dsn-node \
  --from-literal=dsn="${NODE_DSN}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n demo-sentry create secret generic sentry-dsn-python \
  --from-literal=dsn="${PYTHON_DSN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "done:"
echo "  demo-node dsn: ${NODE_DSN}"
echo "  demo-python dsn: ${PYTHON_DSN}"
echo "for examples use:"
echo "  export SENTRY_PROJECT=native"
echo "  export SENTRY_PROJECT=sourcemap-upload"
