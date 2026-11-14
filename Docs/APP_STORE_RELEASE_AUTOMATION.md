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
Режимы metadata/review/status работают на Ubuntu без Xcode/Keychain/Fastlane,
чтобы не ждать свободный Mac. Full/upload используют macOS для бинарного transport.

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

## Следующий полный проход: 0.1.1 (11)

Номер 11 задан для macOS, Finder extension и iOS в project.yml. Release notes EN/RU
дополнены исправлением превью перетаскиваемого хоста на macOS. Этот раздел — план
нового запуска, не подтверждение его успешного выполнения.

1. Смержить PR из dev в main, дождаться зелёных Build and Test и Release automation checks.
2. В App Store Connect → Farport → App Review открыть прежние Draft Submissions
   для iOS и macOS и убрать из них **версию 0.1.1**, подготовленную с билдом 10.
   Версия должна снова стать редактируемой (Prepare for Submission).
   Не удалять приложение, версию или загруженный билд 10. Это требуется только
   пока версия находится в Ready for Review; если её уже отправили в Apple,
   сначала отдельно решить судьбу активного ревью. Workflow не отменяет ревью.
   [Apple: Ready for Review и черновик отправки](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app).
3. GitHub → Actions → Prepare App Store Release → Run workflow:
   branch **main**, platform **both**, mode **full**, build_number **11**,
   artifact_run_id оставить пустым. Нажать Run workflow один раз.
4. Дождаться signed IPA/PKG и их upload/VALID. При запросе Export Compliance
   заполнить ответы владельца для **нового билда 11 отдельно на каждой платформе**
   в TestFlight. Ответы билда 10 автоматически не декларируются за владельца.
5. Если полный запуск остановился только на этом gate, снова Run workflow:
   main / both / **review** / **11**, artifact_run_id пусто. Это использует уже
   загруженные билды без пересборки. Ошибки metadata исправлять через metadata,
   затем review с тем же номером; не запускать новый full с пустым номером.
6. Проверить зелёный итог и READY_FOR_REVIEW для обеих платформ с выбранным билдом
   **0.1.1 (11)**. Перед ручным Submit for Review проверить тексты/скриншоты,
   compliance и Production CloudKit. Submit и публикацию workflow не выполняет.

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

Управляемые uploads определяются полным шаблоном farport-<light|dark>-<scene>-<hash>.png;
простого префикса farport- недостаточно для права на удаление. Точные совпадения вручную загруженных
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
  остановлен ранним аудитом до сборки. Исправлено чтение wildcard/array allowlists
  Apple profiles; фактическая подпись по-прежнему требует точных production values.
- [Full / both, af989f5](https://github.com/panandafog/Farport/actions/runs/43484871300):
  оба архива собраны; исправлен синтаксис optional prefix команды codesign при
  извлечении публичного сертификата. Исправленная команда отдельно проверена на
  настоящей подписи локально, без чтения приватных ключей.
- [Full / both, 7bbdfab — **0.1.1 (10)**](https://github.com/panandafog/Farport/actions/runs/43488614317):
  аудит подтвердил три профиля/сертификаты/production capabilities и публичные URL.
  iOS IPA прошёл проверку архива и экспорта, сохранён до upload, загружен в Apple и
  обработан до VALID. Metadata EN/RU, полная возрастная анкета с read-back и 32 PNG
  iPhone/iPad успешно подготовлены. Этап review остановился на незаполненном
  Export Compliance; после ответа владельца подтверждён отдельным review resume ниже.
  Mac app и Finder extension подписаны/проверены, включая распакованный installer
  PKG, sandbox, profiles, сертификаты и release/demo isolation; PKG сохранён,
  загружен и обработан до VALID. Mac metadata EN/RU и все 20 PNG приняты.
  Mac review также остановился на Export Compliance, затем продолжен без пересборки.
- [Review resume / both / build 10, b88c2c9](https://github.com/panandafog/Farport/actions/runs/43526107337)
  — **полностью успешен** (2026-11-14 по московскому времени). Для IOS и MAC_OS
  Apple подтвердила VALID, выбор точного билда **0.1.1 (10)**, App Review Information,
  metadata EN/RU, checksum/порядок/COMPLETE существующих скриншотов и
  **READY_FOR_REVIEW** версии, черновика и соответствующего review item.
  Прочитан существующий ответ владельца по шифрованию: `non-exempt: false` для
  обеих платформ; автоматизация его не меняла и не подтверждает юридическую
  применимость освобождения. На этом запуске не выполнялись сборка, подпись,
  повторный upload или настройка Xcode: API-only этапы прошли на Linux.
  **Submit for Review и публикация не выполнялись.**
- Артефакты подписанных пакетов: `app-store-ios-43488614317` (~12 MB) и
  `app-store-macos-43488614317` (~18 MB), доступны до 2026-11-27 в full run.
- [Offline release checks для PR, b88c2c9](https://github.com/panandafog/Farport/actions/runs/43493841560):
  95 тестов и Fastlane validation прошли на GitHub, включая safety/portability tests.
  [Обычный CI того же коммита](https://github.com/panandafog/Farport/actions/runs/43493841912)
  также прошёл. Эти проверки не заменяют подтверждение Apple.
- Подготовлен [PR №7](https://github.com/panandafog/Farport/pull/7) с исправлениями
  реального запуска; main автоматически не меняется. Для повторной проверки —
  **status / both / build 10**; для повторения подготовки — review с тем же билдом.
  Перед ручным Submit владелец проверяет актуальность скриншотов, App Privacy,
  применимость ответов по шифрованию и реальную работу Production CloudKit.
