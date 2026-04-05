#!/usr/bin/env bash
# Linux + чистый C: ELF с DWARF. Команда та же, что для отладочных файлов:
#   sentry-cli debug-files upload ...
# dSYM — это формат Apple (macOS/iOS); на Linux заливается ELF (опционально --type elf).
#
# Нативные DIF в Sentry привязываются к проекту по debug id (build-id), не к релизу.
# Разные «имена релизов» здесь — через sentry-cli releases new (для релизов в UI);
# символика подставится по совпадению debug id в событии и загруженных файлах.
#
# export SENTRY_URL="https://sentry.example.com"
# export SENTRY_AUTH_TOKEN="..."
# export SENTRY_ORG="default"
# export SENTRY_PROJECT="my-project"

set -euo pipefail
cd "$(dirname "$0")"

: "${SENTRY_ORG:?set SENTRY_ORG}"
: "${SENTRY_PROJECT:?set SENTRY_PROJECT}"

cc -g -O0 -o app-linux-debug main.c

# Несколько имён релизов в Sentry (опционально; повторный new может завершиться ошибкой — игнор)
for rel in "test-debug@1.0.0" "test-debug@1.0.1" "test-debug@nightly"; do
  sentry-cli releases new --org "$SENTRY_ORG" --project "$SENTRY_PROJECT" "$rel" 2>/dev/null || true
done

echo "=== debug-files upload (один бинарник, один раз или повторно — дубликаты пропускаются) ==="
sentry-cli debug-files upload \
  --org "$SENTRY_ORG" \
  --project "$SENTRY_PROJECT" \
  --type elf \
  --wait \
  app-linux-debug

sentry-cli debug-files check app-linux-debug || true

echo "Готово: Project Settings → Debug Information Files. Релизы: Releases (имена созданы выше)."
