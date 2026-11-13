# Farport — App Store metadata
## Общие поля App Store Connect

| Поле | Значение |
| --- | --- |
| Name | Farport |
| Version | 0.1.1 |
| Bundle ID — обе платформы | `com.panandafog.harbor` — не менять |
| Build | Выбрать загруженную сборку соответствующей платформы; текущий номер в исходниках — 10 |
| Primary Language | English (U.S.), если основная локализация ещё не задана |
| Primary Category | Предлагается [Developer Tools](https://developer.apple.com/app-store/categories/) |
| Copyright | `2026 <правообладатель>` — заполнить |
| Support URL | **Заполнить:** опубликованная страница поддержки с контактами |
| Privacy Policy URL | **Заполнить после публикации:** публичная ссылка на [политику Farport](privacy-policy.md); RTF-копия — `../privacypolicy.rtf` |
| Marketing URL | Необязательно; оставить пустым, пока нет страницы приложения |

### App Review Information — общие поля

| Поле | Значение |
| --- | --- |
| Contact First Name | **Заполнить:** имя контактного лица для App Review |
| Contact Last Name | **Заполнить:** фамилия |
| Contact Email | **Заполнить:** действующий адрес для вопросов ревьюера |
| Contact Phone | **Заполнить:** телефон в международном формате `+…` |
| Sign-in required | **Yes:** для проверки SSH требуется вход на сервер; отдельного аккаунта Farport нет |
| Username | `bandit0` |
| Password | `bandit0` |
| Notes | Один из готовых блоков App Review Notes ниже; адрес и порт сервера указаны в нём |

Это опубликованная учебная учётная запись OverTheWire, а не личные данные
разработчика. Её параметры сверены с [официальной страницей Bandit](https://overthewire.org/wargames/bandit/bandit0.html).
Параметры запасного SSH/SFTP-хоста опубликованы на [странице Rebex](https://www.rebex.net/buru-sftp-server/demo/).

## English (U.S.) — en-US

### Name

```text
Farport
```

### Subtitle

```text
SSH terminal & saved hosts
```

### Promotional Text — iOS / iPadOS

```text
Keep your servers close: SSH terminals, named tabs, jump hosts and optional iCloud host sync.
```

### Promotional Text — macOS

```text
SSH terminals, SFTP transfers and remote folders in Finder. Organize your hosts and tabs, connect through jump hosts and return to tmux sessions.
```

### Description — iOS / iPadOS

```text
Connect to your servers from iPhone and iPad with Farport. Save connection settings, open SSH terminals and keep separate tasks in named tabs.

YOUR SERVERS, READY TO CONNECT

Save hostnames, ports, usernames and connection settings. Authenticate with a password or an imported OpenSSH private key, including passphrase-protected keys. Connect through saved jump hosts with ProxyJump.

A TERMINAL FOR EVERY TASK

Create and rename terminal tabs for each host. Select and copy text, review scrollback, send control keys and use a hardware keyboard. Choose a color scheme, follow the system's light or dark appearance and optionally use the app accent for supported shell prompts and tmux decorations.

RETURN TO YOUR WORK

Use optional tmux sessions to reconnect to work that remains on your server after a connection interruption or an app restart. tmux must already be installed on the server. iOS may disconnect SSH when the app goes into the background; tmux keeps the remote session running on the server.

HOSTS ACROSS YOUR DEVICES

Enable iCloud to sync host profiles and terminal tab definitions between your devices. Passwords, private keys and server-key trust remain on each device; configure credentials separately on a new device. Terminal output is not synced.

Credentials are stored in Keychain. Farport asks you to verify an unfamiliar server's key before connecting. No Farport account is required; you need an SSH server and valid credentials for it.

The iPhone and iPad app provides SSH terminals. SFTP browsing and Finder integration are available in the separate macOS app.
```

### Description — macOS

```text
Work with your servers from a native Mac app. Farport brings saved hosts, SSH terminal tabs, SFTP transfers and remote folders in Finder into one workflow.

TERMINALS FOR YOUR DAILY WORK

Open multiple named terminal tabs for each host. Select and copy text, review scrollback and use control-key shortcuts. Choose a color scheme, follow the system's light or dark appearance and optionally use the app accent for supported shell prompts and tmux decorations.

FILES IN FARPORT AND FINDER

Browse SFTP folders, upload and download individual files, create folders, rename items and delete files or empty folders. Follow transfer progress and cancel a transfer when needed.

Connect a remote folder as a Finder location with read-only or read/write access. Browse files in Finder and open supported files in other Mac apps. Finder integration uses on-demand downloads and synchronization; available operations depend on the server's permissions.

CONNECT THE WAY YOUR SERVERS REQUIRE

Save hostnames, ports, usernames and connection settings. Use a password or an imported OpenSSH private key, including passphrase-protected keys. Connect through saved jump hosts with ProxyJump for SSH, SFTP and Finder access.

RETURN TO YOUR WORK

Optional tmux sessions let you reattach to work that remains on the server after a disconnection or an app restart. tmux must already be installed on the server. Local terminal output remains available after disconnecting while its tab stays open; it is not saved across app restarts.

Enable iCloud to sync host profiles and terminal tab definitions with your other devices. Passwords, private keys and server-key trust stay on each device. Credentials are stored in Keychain, and unfamiliar server keys require your confirmation.

No Farport account is required. You need an SSH/SFTP server and valid credentials for it.
```

### Keywords — iOS / iPadOS

```text
shell,server,remote,console,sysadmin,developer,proxyjump,tmux,icloud,linux,connection
```

### Keywords — macOS

```text
shell,server,remote,console,sftp,finder,transfer,sysadmin,proxyjump,tmux,icloud,linux
```

### What's New in This Version — 0.1.0

Для первой публикации это поле не заполняется. Если App Store Connect уже считает
версию обновлением, используйте этот текст только когда он соответствует диффу
от предыдущего публичного релиза.

```text
Farport brings saved hosts, SSH terminal tabs, ProxyJump connections, optional tmux session recovery and iCloud host-profile sync to Mac, iPhone and iPad. The Mac app also includes SFTP transfers and Finder integration. Available in English and Russian.
```

### App Review Notes — iOS / iPadOS

```text
Farport is an SSH client for user-provided servers. No Farport account or registration is required. The review username/password belong to the public OverTheWire training server below.

1. Add a host using the + button / New Host:
   Name: Bandit SSH
   Hostname: bandit.labs.overthewire.org
   Port: 2220
   Username: bandit0
   Authentication: Password
   Password: bandit0
   Session: Standard SSH
   Initial directory: . (default)
2. Save the host, select it and tap Connect.
3. Review the server fingerprint; after verification, choose Trust & Connect.
4. Try whoami, pwd, ls and uname -s. Type exit to disconnect.
5. Use the terminal tab menu to create another tab or rename a tab.

Published account: https://overthewire.org/wargames/bandit/bandit0.html
This is an external shared training server, not a Farport-operated service.

Backup: test.rebex.net, port 22, username demo, password password. Use Standard SSH and turn off Use App Accent in terminal appearance settings before connecting to this limited shell. Supported commands include help, pwd and ls.

iPhone/iPad provides terminals only; file browsing is macOS-only. Optional tmux mode requires tmux on the chosen server. Backgrounding the app can disconnect SSH; it does not provide indefinite background terminal execution.

iCloud is optional and requires an Apple Account signed into iCloud. Enable host sync in the app on both devices to test it. Synced hosts and tab definitions require credentials and server-key approval on each device. Passwords, private keys and terminal output are not synced.

The submitted Release build has no screenshot/demo switch or preloaded sample hosts. Add the public host above using the normal interface.
```

### App Review Notes — macOS

```text
Farport is an SSH/SFTP client for user-provided servers. No Farport account or registration is required. The review username/password belong to the public OverTheWire training server below.

SSH terminal:
1. Click New Host. Enter name Bandit SSH, hostname bandit.labs.overthewire.org, port 2220, username bandit0, Password authentication, password bandit0. Keep Standard SSH and initial directory . (default).
2. Save, select the host and click Connect. Review the server fingerprint and, after verification, choose Trust & Connect.
3. Try whoami, pwd, ls and uname -s. Type exit to disconnect. Use + in the terminal tab bar to add a tab.
Published account: https://overthewire.org/wargames/bandit/bandit0.html

SFTP and Finder:
1. Add another host: name Rebex SFTP, hostname test.rebex.net, port 22, username demo, Password authentication, password password, initial directory . (default).
2. Save and select it, then open Files. Verify and approve its server key when prompted.
3. Browse /pub and download /readme.txt.
4. Use Connect Folder to Finder. Enter remote folder /pub, select Read Only, connect and use Open in Finder. Files are downloaded on demand.
Published account: https://www.rebex.net/buru-sftp-server/demo/

Rebex is intentionally read-only. Upload, rename and deletion are denied by this server, not by Farport. These external shared accounts are not operated by us and do not provide a writable SFTP/ProxyJump/tmux test environment.

Rebex also has a limited SSH shell: turn off Use App Accent in terminal appearance settings before connecting, use Standard SSH and try help, pwd or ls.

iCloud host/tab sync is optional and requires an Apple Account signed into iCloud. Configure credentials and approve server keys separately on each device. Passwords, private keys and terminal output are not synced. Persistent remote sessions require tmux installed on the selected server.

The submitted Release build has no screenshot/demo switch or preloaded sample hosts. The app connects directly to the configured servers.
```

## Русский — ru

### Name

```text
Farport
```

### Subtitle

```text
SSH-терминал и ваши серверы
```

### Promotional Text — iOS / iPadOS

```text
Ваши серверы под рукой: SSH-терминал, именованные вкладки, подключение через промежуточные хосты и синхронизация профилей через iCloud на iPhone и iPad.
```

### Promotional Text — macOS

```text
SSH-терминал, передача файлов по SFTP и удалённые папки в Finder. Сохраняйте хосты, работайте во вкладках и возвращайтесь к серверным сессиям tmux.
```

### Description — iOS / iPadOS

```text
Подключайтесь к своим серверам с iPhone и iPad через Farport. Сохраняйте параметры подключения, открывайте SSH-терминалы и распределяйте задачи по именованным вкладкам.

ВАШИ СЕРВЕРЫ ПОД РУКОЙ

Сохраняйте адреса, порты, имена пользователей и настройки подключения. Используйте пароль или импортированный приватный ключ OpenSSH, в том числе защищённый парольной фразой. Подключайтесь через сохранённые промежуточные хосты с помощью ProxyJump.

ТЕРМИНАЛ ДЛЯ КАЖДОЙ ЗАДАЧИ

Создавайте и переименовывайте вкладки терминала для каждого хоста. Выделяйте и копируйте текст, просматривайте историю вывода, отправляйте управляющие клавиши и работайте с аппаратной клавиатурой. Выберите цветовую схему и автоматическое переключение светлой и тёмной темы. При желании используйте акцентный цвет приложения для поддерживаемых приглашений оболочки и оформления tmux.

ВОЗВРАЩАЙТЕСЬ К РАБОТЕ

Включите режим tmux, чтобы после разрыва соединения или перезапуска приложения вернуться к сессии, которая продолжает работать на сервере. tmux должен быть заранее установлен на сервере. При уходе приложения в фон iOS может разорвать SSH-соединение; удалённую сессию сохраняет серверный tmux.

ХОСТЫ НА ВАШИХ УСТРОЙСТВАХ

Включите iCloud для синхронизации профилей хостов и списка вкладок между устройствами. Пароли, приватные ключи и доверие к ключам серверов остаются на каждом устройстве: на новом устройстве данные для входа нужно настроить отдельно. Вывод терминала не синхронизируется.

Данные для входа хранятся в Связке ключей. Перед подключением к незнакомому серверу Farport предлагает проверить его ключ. Аккаунт Farport не нужен; для работы необходим SSH-сервер и действующие данные для входа на него.

Версия для iPhone и iPad предназначена для SSH-терминалов. Работа с файлами по SFTP и интеграция с Finder доступны в отдельной версии для macOS. Интерфейс поддерживает русский и английский языки.
```

### Description — macOS

```text
Работайте со своими серверами в нативном приложении для Mac. Farport объединяет сохранённые хосты, вкладки SSH-терминала, передачу файлов по SFTP и удалённые папки в Finder.

ТЕРМИНАЛ ДЛЯ ПОВСЕДНЕВНЫХ ЗАДАЧ

Открывайте несколько именованных вкладок для каждого хоста. Выделяйте и копируйте текст, просматривайте историю вывода и используйте сочетания с управляющими клавишами. Выберите цветовую схему и автоматическое переключение светлой и тёмной темы. При желании используйте акцентный цвет приложения для поддерживаемых приглашений оболочки и оформления tmux.

ФАЙЛЫ В FARPORT И FINDER

Просматривайте папки по SFTP, загружайте и скачивайте отдельные файлы, создавайте папки, переименовывайте объекты и удаляйте файлы или пустые папки. Следите за ходом передачи и отменяйте её при необходимости.

Подключите удалённую папку к Finder в режиме чтения или чтения и записи. Просматривайте файлы в Finder и открывайте поддерживаемые файлы в других приложениях Mac. Интеграция использует загрузку по запросу и синхронизацию; доступные операции зависят от разрешений на сервере.

ПОДКЛЮЧЕНИЯ ПОД ВАШИ ЗАДАЧИ

Сохраняйте адреса, порты, имена пользователей и настройки подключения. Используйте пароль или импортированный приватный ключ OpenSSH, в том числе защищённый парольной фразой. Подключайтесь через промежуточные хосты с помощью ProxyJump для SSH, SFTP и Finder.

ВОЗВРАЩАЙТЕСЬ К РАБОТЕ

Режим tmux позволяет вернуться к сессии на сервере после разрыва соединения или перезапуска приложения. Для этого на сервере должен быть заранее установлен tmux. После отключения локальный вывод терминала остаётся доступен, пока открыта его вкладка; между перезапусками приложения он не сохраняется.

Включите iCloud для синхронизации профилей хостов и списка вкладок с другими устройствами. Пароли, приватные ключи и доверие к ключам серверов остаются на каждом устройстве. Данные для входа хранятся в Связке ключей; незнакомые ключи серверов требуют вашего подтверждения.

Аккаунт Farport не нужен. Для работы необходим SSH/SFTP-сервер и действующие данные для входа на него. Интерфейс поддерживает русский и английский языки.
```

### Keywords — iOS / iPadOS

```text
shell,console,proxyjump,tmux,icloud,linux,сервер,консоль,доступ
```

### Keywords — macOS

```text
sftp,finder,proxyjump,tmux,icloud,linux,файлы,передача,доступ
```

### What's New in This Version — 0.1.0

Для первой публикации поле отсутствует. Текст ниже — заготовка для обновления,
если перечисленные функции действительно новые относительно публичной версии.

```text
Farport объединяет сохранённые хосты, вкладки SSH-терминала, подключения через ProxyJump, восстановление серверных сессий tmux и синхронизацию профилей через iCloud на Mac, iPhone и iPad. Версия для Mac также поддерживает передачу файлов по SFTP и интеграцию с Finder. Доступны русский и английский языки.
```

### App Review Notes — iOS / iPadOS

```text
Farport — SSH-клиент для серверов пользователя. Регистрация и аккаунт Farport не нужны. Логин и пароль в полях для ревью относятся к публичному учебному серверу OverTheWire.

1. Добавьте хост кнопкой + / «Новый сервер»:
   Название: Bandit SSH
   Адрес: bandit.labs.overthewire.org
   Порт: 2220
   Пользователь: bandit0
   Аутентификация: пароль
   Пароль: bandit0
   Сессия: обычный SSH
   Начальная папка: . (по умолчанию)
2. Сохраните хост, выберите его и нажмите «Подключить».
3. Проверьте отпечаток ключа сервера и подтвердите доверие с подключением.
4. Выполните whoami, pwd, ls, uname -s. Команда exit завершит сеанс.
5. Через меню вкладок добавьте или переименуйте вкладку терминала.

Публичные данные: https://overthewire.org/wargames/bandit/bandit0.html
Это внешний общий учебный сервер, мы им не управляем.

Запасной SSH-хост: test.rebex.net, порт 22, пользователь demo, пароль password. Выберите обычный SSH и до подключения выключите «Использовать акцент приложения» в настройках оформления терминала. В ограниченной оболочке доступны help, pwd, ls.

Версия для iPhone/iPad содержит только терминал; файлы доступны на macOS. Режим tmux требует установленного tmux на сервере. При уходе в фон SSH может отключаться; бесконечная фоновая работа не предусмотрена.

iCloud необязателен; для проверки нужен вход в Аккаунт Apple и включённая синхронизация в Farport на обоих устройствах. Данные для входа и доверие к серверу настраиваются отдельно на каждом устройстве. Пароли, приватные ключи и вывод терминала не синхронизируются.

В релизной сборке нет режима скриншотов/демо и готовых хостов. Добавьте указанный сервер через обычный интерфейс.
```

### App Review Notes — macOS

```text
Farport — SSH/SFTP-клиент для серверов пользователя. Аккаунт Farport не нужен. Логин и пароль для ревью относятся к публичному серверу OverTheWire.

SSH:
1. «Новый сервер»: название Bandit SSH, адрес bandit.labs.overthewire.org, порт 2220, пользователь bandit0, вход по паролю bandit0. Оставьте обычный SSH и начальную папку . (по умолчанию).
2. Сохраните, выберите хост и подключитесь. Проверьте отпечаток ключа и подтвердите доверие с подключением.
3. Выполните whoami, pwd, ls, uname -s; exit завершит сеанс. Кнопка + в панели вкладок добавляет терминал.
Данные: https://overthewire.org/wargames/bandit/bandit0.html

SFTP и Finder:
1. Добавьте Rebex SFTP: test.rebex.net, порт 22, пользователь demo, вход по паролю password, начальная папка . (по умолчанию).
2. Сохраните, выберите хост, откройте «Файлы». Проверьте и подтвердите ключ сервера.
3. Откройте /pub и скачайте /readme.txt.
4. Выберите подключение папки к Finder, путь /pub, режим «Только чтение». Подключите и откройте папку в Finder; файлы загружаются по запросу.
Данные: https://www.rebex.net/buru-sftp-server/demo/

Rebex разрешает только чтение. Загрузка на сервер, переименование и удаление запрещены сервером. Эти внешние общие аккаунты не предоставляют среду для проверки записи, ProxyJump и tmux.

Для ограниченной SSH-оболочки Rebex до подключения выключите «Использовать акцент приложения» в оформлении терминала. Используйте обычный SSH; доступны help, pwd, ls.

iCloud необязателен и требует входа в Аккаунт Apple. Данные для входа и доверие к ключам настраиваются на каждом устройстве отдельно. Пароли, приватные ключи и вывод терминала не синхронизируются. Постоянная удалённая сессия требует установленного tmux на выбранном сервере.

В релизе нет режима скриншотов/демо и готовых хостов. Подключения идут напрямую к настроенным серверам.
```

## Перед отправкой

- Заполнить контакты App Review, правообладателя, Support URL и Privacy Policy URL.
  Не вставлять служебные пометки и незаполненные поля в карточку приложения.
- Опубликовать [privacy-policy.md](privacy-policy.md) по доступному без авторизации
  HTTPS-адресу и указать его в Privacy Policy URL. Добавить доступную ссылку на
  опубликованную политику в приложение. Локальный Markdown/RTF-файл не является
  опубликованным URL.
- Публичные аккаунты покрывают SSH и чтение SFTP/Finder, но не запись, ProxyJump
  и tmux. Для проверки этих функций понадобится разрешённая для таких операций
  инфраструктура; не выдавать read-only аккаунт за полноценную среду для записи.
- В этой задаче параметры аккаунтов сверены с сайтами операторов; новые подключения
  не выполнялись. Последняя протокольная проверка в проекте — 2026-10-31, см.
  [App Review hosts](../Docs/AppReview.md). Перед отправкой повторно проверить доступность
  и ключи серверов; внешними сервисами мы не управляем.
- Для iCloud в App Store/TestFlight нужна опубликованная Production-схема CloudKit,
  см. [инструкцию iCloud](../Docs/iCloud.md). Текст карточки не подтверждает, что это
  уже настроено в Apple Developer.
- App Privacy, возрастной рейтинг и export compliance заполнить отдельно по
  фактической поставляемой сборке. Этот файл не является политикой конфиденциальности
  или готовой декларацией сбора данных.

## Источники и лимиты полей

Название/подзаголовок — до 30 символов: [Apple — App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/).
Promotional Text — до 170 символов; Description и What's New — до 4000 символов;
Keywords — до 100 UTF-8 байт; Review Notes — до 4000 байт. What's New недоступно
для первой версии: [Apple — Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information).

Содержание функций сверено с `README.md`, `Docs/Usage.md`, `Docs/Security.md`,
`Docs/AppReview.md`, `SharedUI/TerminalAppearanceSettings.swift`,
`App/FinderControls.swift` и `project.yml`. SFTP/Finder не заявлены как функции iOS,
не обещаются бессрочная фоновая работа, синхронизация секретов или сохранение
локального вывода после перезапуска.

### Проверка длины

Проверены все 22 блока для копирования. Для байтовых ограничений посчитан UTF-8,
включая переводы строк. Сборки и UI-тесты при подготовке метаданных не запускались.

| Поле | en-US | ru | Лимит |
| --- | ---: | ---: | ---: |
| Name | 7 | 7 | 30 символов |
| Subtitle | 26 | 27 | 30 символов |
| Promotional Text — iOS / iPadOS | 112 | 152 | 170 символов |
| Promotional Text — macOS | 145 | 147 | 170 символов |
| Description — iOS / iPadOS | 1639 | 1889 | 4000 символов |
| Description — macOS | 1899 | 2117 | 4000 символов |
| Keywords — iOS / iPadOS | 85 | 82 | 100 байт |
| Keywords — macOS | 85 | 80 | 100 байт |
| What's New in This Version — 0.1.0 | 253 | 305 | 4000 символов |
| App Review Notes — iOS / iPadOS | 1712 | 2755 | 4000 байт |
| App Review Notes — macOS | 2037 | 2974 | 4000 байт |
