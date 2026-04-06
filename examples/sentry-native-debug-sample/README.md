# Загрузка нативных debug-файлов (ELF + DWARF) в Sentry

Минимальный исходник на **C** (`main.c`) собирается в ELF с отладочной информацией (**`-g -O0`**), затем **`sentry-cli debug-files upload`** отправляет файл в проект Sentry как **debug information file (DIF)**. Отдельный краш-репортинг или SDK в этом каталоге не поднимаются — только сборка и upload.

На Linux в Sentry загружается **ELF** (опционально явно `--type elf`). **dSYM** — формат Apple (macOS/iOS); для Linux используется ELF, не dSYM.

**Важно:** нативная символика в Sentry привязывается к событию по **debug id** (build-id в ELF), а не к имени релиза. Скрипт дополнительно создаёт несколько имён релизов через `sentry-cli releases new` — чтобы в UI были записи в **Releases**; на подстановку символов по debug id это не влияет.

## Какой проект создать в Sentry

Чтобы к **этому** репозиторию (пример `examples/sentry-native-debug-sample`) можно было привязать загрузку debug-файлов, в Sentry нужен проект под **нативный** стек — обычно **C/C++** (или аналог **Native**), чтобы артефакты и события согласовывались с ожидаемым типом.

1. Откройте ваш инстанс Sentry (`https://sentry.io` или self-hosted, например `http://sentry.apatsev.org.ru`).
2. Войдите и выберите **организацию** (или создайте новую: **Create organization**).
3. **Projects → Create Project** (или аналог в меню).
4. В качестве платформы выберите **C/C++** / **Native** (или ближайший вариант из мастера для нативных крашей).
5. Задайте **имя проекта** и завершите мастер. После создания откройте **Project Settings → General** и запишите **Project slug** — это значение для `SENTRY_PROJECT`. Slug **организации** виден в URL: `/organizations/<org-slug>/...` — это `SENTRY_ORG`.

Дальше создайте **Auth Token** с правами на загрузку debug-файлов и релизы (см. таблицу ниже) и задайте переменные окружения для `upload-releases.sh`. Отдельно «создавать» исходники не нужно — в каталоге уже есть `main.c`; достаточно компилятора C и скрипта загрузки.

## Требования

- Linux, **GCC/Clang** (`cc` в `PATH`)
- **sentry-cli** с доступом к вашему Sentry
- Созданный в Sentry нативный проект и токен с правами на **Release / Debug files** (или эквивалент для загрузки артефактов и при необходимости релизов)

## Переменные окружения

| Переменная | Обязательно | Описание |
|------------|-------------|----------|
| `SENTRY_AUTH_TOKEN` | да | токен |
| `SENTRY_ORG` | да | slug организации |
| `SENTRY_PROJECT` | да | slug проекта (из **Project Settings → General**) |
| `SENTRY_URL` | нет | self-hosted, например `http://sentry.apatsev.org.ru` |

Скрипт не использует `SENTRY_RELEASE` для символикации: имена релизов (`test-debug@1.0.0` и т.д.) зашиты в `upload-releases.sh` только для демонстрации записей в **Releases**.

### Как получить значения

1. `SENTRY_ORG`: возьмите slug организации из URL, например `https://sentry.example.com/organizations/<org-slug>/`.
2. `SENTRY_PROJECT`: откройте **Project Settings → General Settings → Project Slug**.
3. `SENTRY_AUTH_TOKEN`: создайте Personal Auth Token в **User Settings → API → Auth Tokens** (или `/settings/account/api/auth-tokens/`) с правами, достаточными для `debug-files upload` и при необходимости `releases` (часто `project:releases`, `project:write`, `org:read` — уточните под вашу политику Sentry).

## Запуск

```bash
cd examples/sentry-native-debug-sample
export SENTRY_URL="http://sentry.apatsev.org.ru"
export SENTRY_AUTH_TOKEN="<токен>"
export SENTRY_ORG="<org>"
export SENTRY_PROJECT="<project>"
bash upload-releases.sh
```

Связка с реальными нативными событиями: в приложении с **sentry-native** / SDK для вашей платформы краши должны содержать тот же **build-id**, что и у загруженного ELF, иначе Sentry не сопоставит символы. Имена релизов в скрипте — отдельная демонстрация UI, не замена настройки release в клиенте.

## Где смотреть в Sentry UI

1. **Debug Information Files (основное)**  
   **Settings** → **Projects** → нужный проект → **Debug Information Files** (или **SDK Setup** / **Symbolication** в зависимости от версии). Там должны появиться загруженные файлы; после `sentry-cli debug-files check` в логе скрипта видно, распознаётся ли бинарник.

2. **Релизы (справочно)**  
   В левом меню организации откройте **Releases**. Скрипт создаёт имена `test-debug@1.0.0`, `test-debug@1.0.1`, `test-debug@nightly` — они должны отображаться как отдельные релизы, если `releases new` прошёл успешно.

Названия пунктов меню могут слегка отличаться в зависимости от версии Sentry; загрузку нативной символики удобнее всего проверять в разделе **Debug Information Files** проекта.
