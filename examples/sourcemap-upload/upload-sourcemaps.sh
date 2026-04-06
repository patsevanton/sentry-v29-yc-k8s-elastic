#!/usr/bin/env bash
# Загрузка только JS source maps в релиз Sentry (self-hosted или sentry.io).
# События с тем же release + dist в SDK будут разминифицированы по этим артефактам.
#
# export SENTRY_URL="http://sentry.example.com"
# export SENTRY_AUTH_TOKEN="..."
# export SENTRY_ORG="default"
# export SENTRY_PROJECT="my-js-project"
# export SENTRY_RELEASE="demo-sourcemap@1.0.0"
# export SENTRY_URL_PREFIX="~/"   # как в браузере доступен каталог с app.js (см. README)

set -euo pipefail
cd "$(dirname "$0")"

: "${SENTRY_ORG:?set SENTRY_ORG}"
: "${SENTRY_PROJECT:?set SENTRY_PROJECT}"
: "${SENTRY_AUTH_TOKEN:?set SENTRY_AUTH_TOKEN}"

RELEASE="${SENTRY_RELEASE:-demo-sourcemap@1.0.0}"
URL_PREFIX="${SENTRY_URL_PREFIX:-~/}"

export SENTRY_AUTH_TOKEN
export SENTRY_ORG
export SENTRY_PROJECT
if [[ -n "${SENTRY_URL:-}" ]]; then
  export SENTRY_URL
fi

npm install
npm run build

echo "=== releases new: $RELEASE ==="
npx sentry-cli releases new "$RELEASE" 2>/dev/null || true

echo "=== upload-sourcemaps dist/ (url-prefix: $URL_PREFIX) ==="
npx sentry-cli releases files "$RELEASE" upload-sourcemaps ./dist \
  --url-prefix "$URL_PREFIX"

echo "=== releases finalize ==="
npx sentry-cli releases finalize "$RELEASE"

echo "Готово: Settings → Source Maps для проекта; в SDK укажите release: \"$RELEASE\" (и dist при необходимости)."
