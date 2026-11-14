# Подготовка Farport к App Store

Автоматизация подготовлена 2026-11-13 на основе проверенного workflow Glintwake.
Теперь используются два отдельных ручных workflow: **Upload App Store Build**
заканчивается на **VALID**, а **Prepare App Store Review** — на **READY_FOR_REVIEW**
с проверкой версии, точного билда и review item. Между ними владелец заполняет
Export Compliance, если Apple его запросила. Submit for Review и публикация ручные.
Результаты реальных запусков записываются ниже отдельно от локальных проверок.

## Состав

- `.github/workflows/app-store-release.yml` — **Upload App Store Build**:
  audit → archive/export → сохранить пакет → upload → VALID → read-only compliance check.
  Исходный путь сохранён для совместимости provenance уже подписанных артефактов.
- `.github/workflows/app-store-review.yml` — **Prepare App Store Review**:
  preflight → compliance → metadata/screenshots → выбрать точный билд → review draft → status.
  Без сертификатов, профилей, Xcode и Fastlane; работает на Ubuntu.
- Оба workflow: только workflow_dispatch, environment `app-store`, доверенные main/dev,
  общий concurrency group без отмены запуска и последовательная обработка платформ.
  Обычный Build and Test не получает signing secrets и не загружает ничего в Apple.
- `reporting.py` / `diagnostics.py`: общий итог на странице Summary, причина и следующий
  шаг, таблица iOS/macOS, безопасные error/warning annotations. Финальный job
  **Release result and next steps** выполняется через always(), включая провал audit.
  Отчёт использует только stdlib и доступен при неудачной установке API dependencies.
- `Scripts/release/plan.py`: ранняя общая проверка всех необходимых Secrets,
  сертификатов, трёх профилей и capabilities для Upload; PNG/текстов/URL и состояния
  ревью — для Review. Upload не зависит от заполнения metadata, наличия review contact
  или состояния уже существующего черновика/активного ревью.
  При Upload source=build без номера выбирает свободный целочисленный build по обеим платформам
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

### 1. Upload App Store Build

GitHub → Actions → **Upload App Store Build** → Run workflow, branch main (или dev
для осознанной проверки до merge).

| Input | Значения |
| --- | --- |
| platform | both / ios / macos |
| source | build — собрать; artifact — восстановить уже подписанный пакет |
| build_number | пустой для нового source=build; точный прежний номер для любого повтора |
| artifact_run_id | только для source=artifact; номер первоначального upload/full run |

`build` проверяет подписи архива и экспортированного IPA/PKG, сохраняет пакет перед
Apple upload и дожидается VALID. `artifact` проверяет источник/identity/checksum и
восстанавливает подписанный пакет без пересборки. Exact build и upload receipts
проверяются перед загрузкой; принятый пакет не отправляется повторно.

После VALID запуск **успешен**, даже если требуется Export Compliance. Summary и
warning annotation укажут точный билд, платформу, ссылку на TestFlight и следующий
шаг. Ошибки API/подписи/обработки Apple остаются настоящими ошибками. Состояние
существующей версии/черновика не меняется, выбранный билд не заменяется, metadata
не обновляются. Для самого первого upload отсутствующая платформа регистрируется
до Transporter; существующая карточка не переписывается.

Номер, выбранный автоматически, записан в Summary для обеих платформ. Имя запуска
показывает Upload / переданный номер (или auto) / платформы. При таймауте обработки
или другом повторе **указать тот же номер явно**, не выбирать новый.

### 2. Ответ владельца в Apple

App Store Connect → Farport → TestFlight → нужная платформа → **точная версия/build**
→ Missing Compliance / Manage. Заполнить ответы отдельно для iOS и macOS. Существующие
ответы другого билда не переносятся автоматически. При non-exempt нужна APPROVED
declaration этого приложения, связанная с этим билдом. Workflow не меняет ответы.

### 3. Prepare App Store Review

GitHub → Actions → **Prepare App Store Review** → Run workflow:

| Input | Значения |
| --- | --- |
| platform | both / ios / macos |
| action | prepare — заполнить metadata и подготовить draft; status — только проверить |
| build_number | **обязательный точный номер из Upload Summary** |

`prepare` сначала проверяет compliance, затем обновляет EN/RU metadata и существующие
PNG, выбирает exact VALID build, заполняет review information и создаёт/переиспользует
draft. Успех — подтверждённые Apple READY_FOR_REVIEW версии, draft и review item.
`status` проверяет эти же условия read-only. Подписанный пакет и artifact_run_id
для Review не нужны. Режим не получает signing secrets и не запускает Mac runner.

Если предыдущая версия ещё Ready for Review со старым билдом, владелец убирает
**версию из неподанного draft** в App Store Connect → App Review, возвращая её в
Prepare for Submission. Не удалять приложение, версию или бинарный upload.
Upload можно выполнять до этого; редактирование требуется только для Review.
Активные отправленные ревью не отменяются автоматически. Уже подготовленный exact
билд с совпадающими metadata переиспользуется без изменений.

Пустой первоначальный 1.0/1.0.0 можно перенумеровать только без контента, selected build
и review history, с уже VALID целевой сборкой. Другие черновики/live не переписываются.
Общий App Information, находящийся на ревью/live, только сверяется; изменения требуют
editable состояния. После ошибки prepare повторять его с **тем же build_number**.
Перед ручным Submit проверить свежесть скриншотов, compliance и Production CloudKit.

### Как читать результат

На странице Summary откройте **Release result and next steps**: сверху таблица
обеих выбранных платформ, далее причина остановки и конкретное следующее действие.
Примеры: «Build uploaded · Export Compliance needs the owner's answer»,
«Action required · EXPORT_COMPLIANCE_REQUIRED», «Release step failed · Archive and sign»,
«Ready for review». Для Upload ожидаемый ручной compliance gate не красит запуск
красным. Review без compliance завершается ошибкой на отдельном явно названном шаге,
не создаёт ложный READY и не меняет metadata. Отсутствующие/неоднозначные отчёты и
сбои artifact/post-job тоже делают итог неуспешным, даже если Apple API этап прошёл.

Подписанный IPA/PKG сохраняется **перед upload** как
`app-store-<ios|macos>-<run ID>` на 14 дней; artifact.json содержит происхождение и
checksum. Можно восстанавливать и прежние артефакты исторических full runs по тому же
защищённому пути workflow. Отчёты audit/platform сохраняются и при ошибке. Ключи,
p12, profiles и DerivedData в артефакты не включаются; временное состояние очищается.

### Пример следующего билда

Смержить изменения и дождаться обычного CI. Для нового билда 13:
Upload App Store Build → main / both / source=build / build_number=13 /
artifact_run_id пусто. После VALID заполнить требуемые ответы Apple, затем
Prepare App Store Review → main / both / action=prepare / build_number=13.
Для проверки результата — тот же workflow с action=status. Submit остаётся ручным.
Номер 13 задан в project.yml для обеих платформ и Finder extension;
его сборка и загрузка пока не выполнялись.

## Метаданные, PNG и ограничения

Источник: `AppStore/app-store-metadata.md`. Copyright/контакты взяты из политики.
Телефон — Secret, опубликованные review credentials — Bandit bandit0/bandit0;
адрес/порт и запасной Rebex указаны в notes. Аккаунты внешние, не гарантируют
writable SFTP/ProxyJump/tmux. Новые подключения к ним в этой задаче не выполняются.

Публичные страницы используют фактическую default branch **main**:
- [Support](https://github.com/panandafog/Farport/blob/main/AppStore/support.md)
- [Privacy](https://github.com/panandafog/Farport/blob/main/AppStore/privacy-policy.md)

Перед Review prepare URL проверяются без авторизации; сначала страницы должны
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
APPROVED declaration того же приложения. Пока ответа/документа нет, Upload успешно заканчивается на VALID,
а Review prepare останавливается до изменений metadata. После оформления повторить
Prepare App Store Review → prepare с прежним build_number.
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
  реального запуска; main автоматически не меняется. Для повторной проверки старого билда —
  **Prepare App Store Review / status / both / build 10**; для подготовки — prepare.
  Перед ручным Submit владелец проверяет актуальность скриншотов, App Privacy,
  применимость ответов по шифрованию и реальную работу Production CloudKit.

- [Исторический full run №5 — 0.1.1 (11)](https://github.com/panandafog/Farport/actions/runs/43574924458):
  подписанные iOS/macOS пакеты загружены, VALID и metadata/screenshots подтверждены;
  остановка на ответах владельца Export Compliance.
- [Review resume №6 — 0.1.1 (11)](https://github.com/panandafog/Farport/actions/runs/43577642798):
  успешен для обеих платформ, exact build 11 выбран, READY_FOR_REVIEW подтверждён Apple.
  Этот повтор ещё использовал прежние inputs mode=review; новый интерфейс описан выше.
- Новая оркестрация проверена реальными запусками: [Upload build 12](https://github.com/panandafog/Farport/actions/runs/43582582313)
  успешно завершился на VALID, [Review build 12](https://github.com/panandafog/Farport/actions/runs/43585743457)
  подтвердил READY_FOR_REVIEW для обеих платформ после освобождения прежнего draft.
  Билд 13 подготовлен в исходниках, но его сборка/загрузка ещё не выполнялись.
