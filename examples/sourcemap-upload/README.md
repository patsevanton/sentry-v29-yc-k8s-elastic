# Загрузка JS source maps в Sentry

Минифицированный бандл `dist/app.js` + `dist/app.js.map` собираются **esbuild**, затем **`sentry-cli releases files … upload-sourcemaps`** отправляет артефакты в выбранный **release**. Отдельный рантайм или браузерный SDK в этом каталоге не поднимаются — только сборка и upload.

## Какой проект создать в Sentry

Чтобы к **этому** репозиторию (пример `examples/sourcemap-upload`) можно было привязать загрузку source maps, в Sentry нужен обычный **проект под клиентский JavaScript** — артефакты привязываются к **организации**, **slug проекта** и **имени релиза**.

1. Откройте ваш инстанс Sentry (`https://sentry.io` или self-hosted, например `http://sentry.apatsev.org.ru`).
2. Войдите и выберите **организацию** (или создайте новую: **Create organization**).
3. **Projects → Create Project** (или аналог в меню).
4. В качестве платформы выберите **Browser** / **JavaScript** / **React** и т.п. — для source maps через CLI важно, чтобы проект был **frontend/JS**; конкретный шаблон (Vanilla vs React) на загрузку `.map` почти не влияет.
5. Задайте **имя проекта** и завершите мастер. После создания откройте **Project Settings → General** и запишите **Project slug** — это значение для `SENTRY_PROJECT`. Slug **организации** виден в URL: `/organizations/<org-slug>/...` — это `SENTRY_ORG`.

Дальше создайте **Auth Token** с правами на релизы (см. таблицу ниже) и задайте переменные окружения для `upload-sourcemaps.sh`. Локально в этом каталоге уже есть минимальный npm-проект (`package.json`, `src/index.js`); отдельно «создавать» его не нужно — достаточно `npm install` и скрипта загрузки.

## Требования

- Node.js 18+
- Созданный в Sentry JS-проект и токен с правами на **Release / Artifact uploads**

## Переменные окружения

| Переменная | Обязательно | Описание |
|------------|-------------|----------|
| `SENTRY_AUTH_TOKEN` | да | токен |
| `SENTRY_ORG` | да | slug организации |
| `SENTRY_PROJECT` | да | slug проекта (из **Project Settings → General**) |
| `SENTRY_URL` | нет | self-hosted, например `http://sentry.apatsev.org.ru` |
| `SENTRY_RELEASE` | нет | имя релиза, по умолчанию `demo-sourcemap@1.0.0` |
| `SENTRY_URL_PREFIX` | нет | префикс URL, под которым в проде отдаётся каталог с `app.js` (см. ниже) |

### Как получить значения

1. `SENTRY_ORG`: возьмите slug организации из URL, например `https://sentry.example.com/organizations/<org-slug>/`.
2. `SENTRY_PROJECT`: откройте **Project Settings → General Settings → Project Slug**.
3. `SENTRY_AUTH_TOKEN`: создайте Personal Auth Token в **User Settings → API → Auth Tokens** (или `/settings/account/api/auth-tokens/`) с правами на релизы/артефакты (обычно `project:releases` и `org:read`).

## `SENTRY_URL_PREFIX`

Должен совпадать с тем, как браузер загружает минифицированный файл. Примеры:

- Файл открывается как `https://example.com/app.js` → `~/`
- Как `https://example.com/static/app.js` → `~/static`
- Как `https://cdn.example.com/assets/app.js` → `~/assets` (если origin в событии совпадает с тем, что ожидает Sentry для маппинга; при необходимости см. [документацию](https://docs.sentry.io/platforms/javascript/sourcemaps/) по `url-prefix` и `dist`).

По умолчанию в скрипте задано `~/` — удобно, если вы тестируете с корня origin.

## Запуск

```bash
cd examples/sourcemap-upload
export SENTRY_URL="http://sentry.apatsev.org.ru"
export SENTRY_AUTH_TOKEN="<токен>"
export SENTRY_ORG="<org>"
export SENTRY_PROJECT="<project>"
bash upload-sourcemaps.sh
```

Связка с реальными ошибками: в приложении с `@sentry/browser` / `@sentry/react` задайте **`release`** (и при использовании — **`dist`**) так же, как `SENTRY_RELEASE` при upload, иначе Sentry не применит карты к стеку.

## Где смотреть в Sentry UI

1. **Релиз и артефакты (основное)**  
   В левом меню организации откройте **Releases** (иногда в группе **Insights**). Найдите релиз с тем же именем, что `SENTRY_RELEASE` (по умолчанию `demo-sourcemap@1.0.0`), откройте его. На странице релиза откройте вкладку **Artifacts** или **Files** — там должны быть загруженные `app.js`, `app.js.map` и связанные записи. Прямой вид URL в self-hosted обычно такой: `/organizations/<org>/releases/<release>/` (вкладка с файлами релиза).

2. **Настройки проекта (справочно)**  
   **Settings** → **Projects** → нужный проект → раздел **Source Maps** — страница про подключение source maps и часто ссылки на документацию; сами загруженные через CLI файлы удобнее смотреть в пункте 1.

Названия вкладок могут слегка отличаться в зависимости от версии Sentry, но путь всегда через **Releases** → конкретный **release** → список артефактов этого релиза.
