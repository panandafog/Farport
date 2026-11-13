# Подготовка Farport к App Store

Автоматизация подготовлена 2026-11-13 на основе проверенного workflow Glintwake.
Окончание процесса — **черновик READY_FOR_REVIEW**, с проверкой версии, точной
сборки и review item. Submit for Review и публикация остаются ручными.
Результаты реальных запусков записываются ниже отдельно от локальных проверок.

## Состав

- `.github/workflows/app-store-release.yml`: только workflow_dispatch, environment
  `app-store`, доверенные ветки main/dev, последовательная обработка платформ.
  Обычный Build and Test не получает signing secrets и не загружает ничего в Apple.
- `Scripts/release/plan.py`: ранняя общая проверка всех необходимых Secrets,
  сертификатов, трёх профилей, capabilities, PNG/текстов/URL, состояния Apple.
  При `full` без номера выбирает свободный целочисленный build по обеим платформам
  и Apple upload receipts. Выбранный номер показывается в Summary.
- `metadata.py`: читает основной Markdown, не дублирует описания в JSON.
  Выбирает отдельные Description/Promotional Text/Keywords/Review Notes платформы;
  русский API locale — `ru`, папки — `ru-RU`.
- `signing.py`: временный изолированный keychain; отдельные профили приложения
  и Finder extension, общий distribution certificate, отдельный installer certificate.
  Проверяет подписи и embedded profiles архива и экспортированного IPA/PKG,
  включая фактическую подпись extension в распакованном PKG.
- `asc.py` / `cli.py`: версии/build, metadata/assets, review information, draft,
  точный read-back. API allowlist не содержит submit/publish/cancel/price endpoints.
- `fastlane/Fastfile`: только бинарный transport; metadata/screenshots/version
  updates/precheck/submit отключены. Fastlane и Python dependencies закреплены.
- `artifact_source.py`: восстановление из завершённого ручного release run того же
  репозитория и доверенной ветки. Проверяются repo/run/workflow/commit SHA,
  platform/version/build и SHA-256 пакета. PR/fork artifacts запрещены.

Project generation: **только** `sh Scripts/xcodegen.sh generate`. Перед архивом
выполняются lint, generated-file diff, checkout-name regression, package locks,
sandbox configuration и `prepare-terminal-build.sh` (Metal Toolchain).
Архивы используют `-onlyUsePackageVersionsFromResolvedFile` и
`-skipPackagePluginValidation`; sandbox плагинов не отключается.

Схемы: `Farport iOS` и `Farport`; только Release, никогда Local/Demo.
Bundle IDs/CloudKit/App Group/Keychain остаются прежними. Номер применяется ко
всем targets одновременно. Release entitlement files требуют production push
и CloudKit Production; Debug/Local entitlement files не меняются.

## Настройка Secrets

GitHub → Farport → Settings → Environments → **app-store**.
Значения не печатать в лог, чат или репозиторий. Base64 — одной строкой,
например `base64 -i /path/to/file | tr -d '\n' | pbcopy`, затем вставить в GitHub.
Наличие записи не доказывает корректность: preflight проверяет содержимое.

| Secret | Назначение |
| --- | --- |
| ASC_KEY_ID | Team API Key ID с доступом App Manager/Admin к Farport |
| ASC_ISSUER_ID | Issuer ID команды |
| ASC_PRIVATE_KEY_P8_BASE64 | Оригинальный приватный .p8, base64 |
| ASC_REVIEW_CONTACT_PHONE | Телефон владельца/контакта ревью в международном формате |
| IOS_DISTRIBUTION_P12_BASE64 / IOS_DISTRIBUTION_P12_PASSWORD | Apple Distribution certificate **с приватным ключом** |
| IOS_PROVISION_PROFILE_BASE64 | **App Store Connect**, com.panandafog.harbor, iOS |
| MAC_APP_DISTRIBUTION_P12_BASE64 / MAC_APP_DISTRIBUTION_P12_PASSWORD | Apple Distribution / Mac App Store Application certificate с ключом |
| MAC_PROVISION_PROFILE_BASE64 | **Mac App Store Connect**, com.panandafog.harbor |
| MAC_FINDER_PROVISION_PROFILE_BASE64 | **Mac App Store Connect**, com.panandafog.harbor.finder |
| MAC_INSTALLER_P12_BASE64 / MAC_INSTALLER_P12_PASSWORD | **Mac Installer Distribution**, не Developer ID Installer |

Общие Team key и сертификаты можно использовать для двух проектов. Профили —
именно Farport, с его production capabilities. Mac-профили должны включать один
и тот же импортированный distribution certificate и shared App Group/Keychain.
Профиль extension не требует CloudKit/push. iOS не получает Mac App Group/File Provider.

Опциональные environment variables: `RELEASE_MACOS_RUNNER` (по умолчанию macos-26),
`RELEASE_XCODE_APP` (путь Xcode.app на runner). Требуется Xcode 26.3+ и Metal Toolchain.
Рекомендуется ограничить environment ветками main/dev; настройки защиты меняет владелец.
Workflow сам дополнительно проверяет ветку и repository. Fork/PR triggers отсутствуют.

## Запуск и повторы

Actions → **Prepare App Store Release** → Run workflow.

| Input | Значения |
| --- | --- |
| platform | both / ios / macos |
| mode | full / upload / metadata / review / status |
| build_number | пустой только для нового full; для повтора **тот же выбранный номер** |
| artifact_run_id | нужен для upload: run ID сохранённого подписанного пакета |

- **full**: audit → archive/export → сохранить Artifact → upload → дождаться VALID
  → metadata/screenshots → exact build/review detail → draft → status.
- **upload**: без пересборки восстановить подписанный пакет, далее полный путь.
- **metadata**: только editable metadata/screenshots; подпись/Transporter не нужны.
- **review**: дождаться существующей сборки, выбрать её, настроить review detail,
  подготовить draft, проверить результат; тексты и скриншоты должны уже совпадать.
- **status**: read-only проверка результата; без подписи/загрузки/изменений Apple.
  Без build_number использует номер project.yml, поэтому для CI override указывать явно.

Не менять build для повтора после таймаута Apple. Exact build и buildUploads receipts
проверяются до новой загрузки. Провал/expired/invalid требует осознанно нового номера.
Платформа, которой ещё нет, создаётся **до Transporter**, иначе Mac Apple ID не находится.
Пустой первоначальный 1.0/1.0.0 можно перенумеровать только без контента, selected build
и review history, с уже VALID целевой сборкой. Другие черновики/live не переписываются.
Общий App Information, уже находящийся на ревью/live, только сверяется; изменения
требуют разрешённого editable состояния. Активные ревью не отменяются.

Подписанный IPA/PKG сохраняется **перед upload** как
`app-store-<ios|macos>-<run ID>` на 14 дней; рядом artifact.json с происхождением
и checksum. Нечувствительный report.json/summary.md сохраняются и при ошибке.
Ключи/p12/profiles и DerivedData не включаются в артефакты; временный keychain
и только установленные этим запуском профили очищаются в always-этапе.

## Метаданные, PNG и ограничения

Источник: `AppStore/app-store-metadata.md`. Copyright/контакты взяты из политики.
Телефон — Secret, опубликованные review credentials — Bandit bandit0/bandit0;
адрес/порт и запасной Rebex указаны в notes. Аккаунты внешние, не гарантируют
writable SFTP/ProxyJump/tmux. Новые подключения к ним в этой задаче не выполняются.

Публичные страницы используют фактическую default branch **main**:
- [Support](https://github.com/panandafog/Farport/blob/main/AppStore/support.md)
- [Privacy](https://github.com/panandafog/Farport/blob/main/AppStore/privacy-policy.md)

Перед `full`/`metadata` URL проверяются без авторизации; сначала страницы должны
быть опубликованы на main. Для обновления нужны `AppStore/release-notes/<version>`.
Тексты 0.1.1 описывают порядок, режим вкладок, исправления iCloud и терминала.

Готовые кадры 1–2 ноября не переснимаются. Порядок: light по номеру сцены, затем dark.
На язык: Mac 10 (1280×800), iPhone 8 (1320×2868), iPad 8 (2064×2752).
Лимит Apple — до 10 на слот; PNG без alpha/transparency. Кадры host settings
предшествуют новым режимам вкладок/значению по умолчанию: владелец должен проверить
актуальность перед Submit. Workflow не запускает capture/UI tests и сообщает об этом.

Собственные uploads имеют префикс farport-. Точные совпадения вручную загруженных
PNG переиспользуются по checksum, без удаления/переименования. Чужие несовпадающие
изображения останавливают этап с диагностикой. Устаревшие **управляемые** изображения
удаляются после замены; если заняты все 10 мест, только управляемые устаревшие
резервации освобождаются раньше. При ошибке повторить metadata; чужие файлы не удаляются.
Для каждого файла показываются locale/device/theme/номер и состояние обработки;
подписанные storage URL и токены не логируются.

Duo: официальный OpenAPI, скачанный **2026-11-13**, версия **4.6**, не содержит Duo
в ScreenshotDisplayType. Closed/Open PNG валидируются (1398×2034 / 2853×2007),
но исключены через displayType=null/optional=true. Не отправлять в обычный iPhone
slot и не придумывать enum. Когда Apple добавит слоты, обновить config и реальную проверку.

## Privacy, encryption, возраст и решения владельца

Подробности и официальные источники — [Release compliance audit](ReleaseCompliance.md).
Workflow не выставляет цену/территории/Content Rights/DSA/legal/privacy labels
и не разворачивает CloudKit Production schema. Существующие ответы Apple не
считаются доказательством, что вся эксплуатационная проверка выполнена.

Возрастная анкета включает полный набор полей и read-back. Ответы по рекламе,
встроенному контенту и платежам обоснованы кодом; пограничные возможности произвольного
remote content (`unrestrictedWebAccess`, `userGeneratedContent`, `messagingAndChat`)
по умолчанию читаются из существующей анкеты владельца. Если их нет, workflow
попросит явно определить ответы; он не копирует возрастные решения игры.

Шифрование: не задаём ITSAppUsesNonExemptEncryption=false и не PATCH-им этот ответ.
Exact build должен иметь ответ владельца в Apple; для non-exempt нужна связанная
APPROVED declaration того же приложения. Пока ответа/документа нет, архив и загрузка
возможны, но review gate остановится. После оформления — `review`, прежний build.
Французская декларация может понадобиться при доступности во Франции; территории
не отключаются автоматически. 2026-11-13 владелец сообщил, что декларацию ещё не оформлял.

Иконка: происхождение MediaPlayer/Trackfold сохранено в истории. **2026-11-13 владелец
явно подтвердил оставить текущую** для этой загрузки; замена не блокирует этот запуск.
Решение не является подтверждением прав на любые будущие сторонние ассеты.

## Проверки

```sh
python3 -m pip install -r Scripts/release/requirements.txt
python3 -m unittest discover -s Tests/ReleaseAutomation -v
bundle install
bundle exec ruby Scripts/release/check-fastlane.rb
sh Scripts/lint.sh
sh Scripts/xcodegen.sh generate
sh Scripts/verify-project-generation.sh
xcrun swift Scripts/verify-package-locks.swift
xcrun swift Scripts/verify-sandbox.swift
```

Offline-тесты моделируют API, состояния и retries, но не доказывают distribution
readiness. Настоящие подписи/processing/draft подтверждаются только реальными запусками.
Обычный release-checks CI выполняет эти offline Python/Fastlane проверки без Secrets.

## Реальные запуски

- [Первый full / both, dev ac41c3a](https://github.com/panandafog/Farport/actions/runs/43484055247):
  остановлен ранним аудитом CloudKit allowlist профиля, **до архива/подписи/загрузки**.
  Проверка исправлена для Apple wildcard/array allowlists; значения реальной подписи
  по-прежнему должны точно совпадать с production entitlements.
- [Offline release checks](https://github.com/panandafog/Farport/actions/runs/43483650989):
  91 тест и Fastlane option validation прошли на GitHub после перехода на Ruby 3.4.
- Реальная подпись/загрузка/READY_FOR_REVIEW пока не подтверждены. Последующие результаты
  добавляются только по данным Apple; локальные проверки не заменяют distribution run.
