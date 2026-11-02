# Farport Privacy Policy / Политика конфиденциальности Farport

Effective date / Дата вступления в силу: **2026-11-02**

## English

### About this policy

Farport is an SSH client for Mac, iPhone and iPad, with SFTP and Finder integration
on Mac. It is developed by Andrei Pantiukhin (the developer). This policy describes
how Farport handles information when you use the app or contact the developer.
You do not need to register a Farport account.

The developer does not operate a backend that receives your SSH sessions, server
credentials or transferred files. The app processes information on your device,
connects to servers you configure and, if you enable synchronization, uses Apple's
iCloud service as described below. The developer does not sell your personal information.

### Information processed on your device

Farport uses the information you provide to deliver its features:

- **Host profiles:** server names and addresses, ports, usernames, authentication
  types, initial directories, notes, jump-host routes and session preferences.
- **Workspace and settings:** terminal tab identifiers, names and order, selected
  host and tab, interface preferences and connection-related state.
- **Credentials and server trust:** passwords, imported private keys, key passphrases
  and trusted server-key fingerprints. These are stored using Apple's Keychain;
  credentials are also held in memory when the app needs them for connections.
- **Terminal content:** commands, other input and output from your remote sessions.
  Local terminal history is held in memory while the terminal is retained; Farport
  does not save it as a transcript across app restarts.
- **Files on Mac:** remote file names, paths and metadata, files you choose to upload
  or download, and Finder connection information. Finder integration can retain
  downloaded files and metadata in system-managed local caches, including after
  Farport closes. Opening a file in another app gives that app access to the file.

Host profiles, notes, workspace metadata and synchronization records are stored in
the app's local data files. Farport does not separately encrypt these local metadata
files. Do not put passwords or private keys in host names, tab names or notes.

### Connections to your servers

When you connect, Farport sends the information needed to authenticate and carry
out your actions to the server you selected. This can include your username,
password authentication, commands, terminal input and uploaded files. Private-key
authentication uses the key on your device; Farport does not upload the private key
or its passphrase to the server.

Connections use SSH, including SFTP file transfers. If you configure ProxyJump,
connections pass through your selected gateway servers. Servers and gateways can
observe connection information such as your IP address, and their operators may
retain logs or remote content according to their own policies and configuration.
The developer does not control those servers, their storage or their privacy practices.

Farport requests local-network access when needed to reach servers on your local
network. You can control this permission in your device's system settings. On Mac,
file import, export and Finder integration also use the access you grant through
the operating system.

### Optional iCloud synchronization

iCloud synchronization is off until you enable it. When enabled, Farport stores
host profiles and terminal tab definitions in a private CloudKit database associated
with your Apple Account, so your devices can synchronize them. This includes host
identifiers, names, addresses, ports, usernames, authentication types, notes, initial
directories, jump-host references, session preferences and tab identifiers, names
and order. Synchronization also uses record identifiers, revision information and
deletion markers to reconcile changes.

Passwords, private keys, key passphrases, trusted server-key fingerprints, terminal
input/output, transferred file contents and Finder locations are not included in
Farport's iCloud host synchronization. Credentials and trust must be configured
separately on each device.

Farport uses CloudKit's encrypted record fields for profile content. Apple operates
iCloud and handles the service under its own [privacy policy](https://www.apple.com/legal/privacy/).
The developer does not receive a copy of your private CloudKit records through a
developer-operated service. This is not a promise of a separate, app-managed
end-to-end encryption system.

Disabling synchronization stops further app synchronization but keeps existing
local and iCloud data. Changing your Apple Account does not erase the local host
library. If you enable synchronization with another account, the local profiles
can be uploaded to that account after the app's confirmation.

### Diagnostics, advertising and tracking

Farport does not include advertising, third-party behavioral analytics, tracking
SDKs or a developer-operated crash-reporting service. The app does not use
advertising identifiers or advertising cookies.

Connection errors and status messages are processed locally and may include server
addresses, usernames, paths or protocol details. They are not automatically sent
to the developer by Farport. Apple may process or share app diagnostics and usage
information under its platform services and the sharing choices available in your
system settings. See [Apple's privacy policy](https://www.apple.com/legal/privacy/).

### Support correspondence

If you email the developer, the developer receives your email address, your message
and any files, screenshots or diagnostics you choose to attach. This information
is used to respond to your request and investigate the issue. Email providers
process the correspondence to deliver and store it. Do not include passwords,
private keys or confidential terminal output in support messages.

Support correspondence is kept while needed to handle your request and related
follow-up, or to meet applicable obligations. You may request access, correction
or deletion of information you sent to support using the contact address below.

### Retention, deletion and your choices

You can edit or delete saved hosts, close terminal tabs, forget trusted server keys,
disconnect Finder locations and turn off iCloud synchronization in Farport.

Deleting a host removes it from the active local host library. Associated app-owned
credential references and Keychain items are retired as part of the app's cleanup;
separately retained Finder data, caches or backups may remain. If synchronization
is enabled, the host deletion is queued for propagation to iCloud and your other
devices when synchronization succeeds.

The current version retains synchronization deletion markers and record identifiers
to prevent deleted entries from returning. It can also retain local recovered
versions of conflicting profiles, which you can dismiss separately. Deleting a
host or disabling synchronization is not a complete erasure of all synchronization
metadata. Farport does not currently provide an in-app command to erase the entire
private CloudKit database.

Downloaded or exported files, system-managed Finder caches, Keychain items and
backups are not necessarily all removed by uninstalling the app. Use the relevant
system, file-management and backup controls to manage those copies. Deleting a host
or disconnecting does not delete files, logs or tmux sessions on a remote server;
manage those on that server.

The developer cannot retrieve your device's local app data, Keychain secrets or
private CloudKit records through a Farport backend. Contact the developer for
questions about the app's data controls or information you supplied directly to support.

### Security

Farport uses SSH for server connections, Keychain for credentials and explicit
server-key verification. You should verify server fingerprints, protect your devices
and Apple Account, and use only servers you trust. No method of electronic storage
or network communication can guarantee absolute security.

### Children and external services

Farport is a general-purpose developer tool and is not designed specifically for
children. The developer does not knowingly request personal information from
children. If you believe a child has sent personal information to support, contact
the developer to request its removal.

Remote servers, Apple services, other apps used to open files and external websites
have their own privacy practices. Review the policies of the services you choose
to use with Farport.

### Changes and contact

This policy may be updated when the app or its data practices change. An updated
policy will show a new effective date on this page.

For privacy questions or requests, contact **Andrei Pantiukhin** at
[panandafog@icloud.com](mailto:panandafog@icloud.com).

## Русский

### Об этой политике

Farport — SSH-клиент для Mac, iPhone и iPad с поддержкой SFTP и Finder на Mac.
Разработчик — Андрей Пантюхин (Andrei Pantiukhin). Эта политика описывает обработку
информации при использовании приложения и обращении к разработчику.
Для работы не нужна регистрация аккаунта Farport.

Разработчик не обслуживает серверную систему, получающую ваши SSH-сеансы, данные
для входа или передаваемые файлы. Приложение обрабатывает информацию на вашем
устройстве, подключается к настроенным вами серверам и, если вы включите
синхронизацию, использует iCloud компании Apple, как описано ниже.
Разработчик не продаёт ваши персональные данные.

### Информация на вашем устройстве

Farport использует предоставленную вами информацию для работы своих функций:

- **Профили хостов:** названия и адреса серверов, порты, имена пользователей, способы
  аутентификации, начальные папки, заметки, маршруты через промежуточные хосты и
  настройки сессий.
- **Рабочее пространство и настройки:** идентификаторы, названия и порядок вкладок
  терминала, выбранные хост и вкладка, параметры интерфейса и состояние подключений.
- **Данные для входа и доверие к серверам:** пароли, импортированные приватные ключи,
  парольные фразы и отпечатки доверенных ключей серверов. Они хранятся в Связке ключей
  Apple; данные для входа также находятся в памяти, когда нужны для подключений.
- **Содержимое терминала:** команды, другой ввод и вывод удалённых сессий.
  Локальная история находится в памяти, пока сохраняется экземпляр терминала;
  Farport не записывает её в журнал для восстановления после перезапуска.
- **Файлы на Mac:** названия, пути и метаданные удалённых файлов, выбранные вами
  файлы для загрузки и скачивания, параметры подключений Finder. Finder может
  сохранять скачанные файлы и метаданные в локальном системном кэше, в том числе
  после закрытия Farport. При открытии файла в другом приложении оно получает
  доступ к этому файлу.

Профили, заметки, метаданные рабочего пространства и записи синхронизации хранятся
в локальных файлах приложения. Farport не шифрует эти локальные файлы метаданных
отдельно. Не помещайте пароли и приватные ключи в названия хостов, вкладок и заметки.

### Подключения к вашим серверам

При подключении Farport передаёт выбранному серверу информацию, необходимую для
аутентификации и выполнения ваших действий. Она может включать имя пользователя,
аутентификацию по паролю, команды, ввод терминала и загружаемые файлы. При входе по
приватному ключу он используется на устройстве; Farport не загружает сам приватный
ключ или его парольную фразу на сервер.

Подключения используют SSH, включая передачу файлов по SFTP. Если настроен
ProxyJump, соединения проходят через выбранные вами промежуточные серверы.
Серверы и шлюзы могут видеть сведения о соединении, например ваш IP-адрес, а их
операторы — сохранять журналы и удалённое содержимое согласно своим настройкам
и политикам. Разработчик не управляет этими серверами, их хранилищами и обработкой данных.

Для подключения к серверам в локальной сети Farport при необходимости запрашивает
соответствующее разрешение. Вы можете управлять им в системных настройках
устройства. На Mac импорт, экспорт и интеграция с Finder также используют доступ,
который вы предоставляете через операционную систему.

### Необязательная синхронизация iCloud

Синхронизация iCloud выключена, пока вы её не включите. После включения Farport
сохраняет профили хостов и описания вкладок терминала в частной базе CloudKit,
связанной с вашим Аккаунтом Apple, для синхронизации между устройствами. Передаются
идентификаторы, названия и адреса хостов, порты, имена пользователей, способы
аутентификации, заметки, начальные папки, ссылки на промежуточные хосты, настройки
сессий, а также идентификаторы, названия и порядок вкладок. Для согласования
изменений также используются идентификаторы записей, сведения о версиях и отметки удаления.

Пароли, приватные ключи, парольные фразы, отпечатки доверенных ключей серверов,
ввод и вывод терминала, содержимое передаваемых файлов и подключения Finder
не входят в синхронизацию хостов через iCloud. Данные для входа и доверие к серверам
нужно настроить отдельно на каждом устройстве.

Для содержимого профилей Farport использует шифруемые поля записей CloudKit.
Сервисом iCloud управляет Apple согласно своей
[политике конфиденциальности](https://www.apple.com/legal/privacy/).
Разработчик не получает копии ваших частных записей CloudKit через собственный
серверный сервис. Это не означает наличия отдельной системы сквозного шифрования,
которой управляет само приложение.

Отключение синхронизации останавливает дальнейшую синхронизацию приложения, но
сохраняет существующие локальные данные и данные iCloud. Смена Аккаунта Apple
не очищает локальную библиотеку хостов. Если включить синхронизацию с другим
аккаунтом, локальные профили могут быть загружены в него после подтверждения в приложении.

### Диагностика, реклама и отслеживание

Farport не содержит рекламы, сторонней поведенческой аналитики, SDK отслеживания
или собственного сервиса отправки отчётов о сбоях разработчику. Приложение не
использует рекламные идентификаторы или рекламные cookie.

Ошибки подключения и сообщения о состоянии обрабатываются локально и могут
содержать адреса серверов, имена пользователей, пути и технические сведения
протокола. Farport не отправляет их разработчику автоматически. Apple может
обрабатывать или передавать диагностику и статистику использования приложения
в рамках своих платформенных сервисов и выбранных вами системных настроек обмена
данными. См. [политику конфиденциальности Apple](https://www.apple.com/legal/privacy/).

### Обращения в поддержку

Если вы пишете разработчику по электронной почте, он получает ваш адрес,
сообщение и приложенные вами файлы, скриншоты или диагностику. Эта информация
используется для ответа и разбора проблемы. Почтовые сервисы обрабатывают
переписку для её доставки и хранения. Не присылайте пароли, приватные ключи
или конфиденциальный вывод терминала.

Переписка хранится, пока нужна для обработки обращения и связанных уточнений
или выполнения применимых обязательств. Вы можете запросить доступ, исправление
или удаление информации, отправленной в поддержку, по контактному адресу ниже.

### Хранение, удаление и ваши настройки

В Farport можно изменять и удалять хосты, закрывать вкладки терминала, забывать
доверенные ключи серверов, отключать подключения Finder и синхронизацию iCloud.

Удаление хоста убирает его из действующей локальной библиотеки. Связанные ссылки
на данные для входа и принадлежащие приложению записи Связки ключей выводятся
из использования и очищаются приложением; отдельно сохранённые данные Finder,
кэш и резервные копии могут остаться. Если синхронизация включена, удаление
передаётся в iCloud и на другие устройства после успешной синхронизации.

Текущая версия сохраняет отметки удаления и идентификаторы записей синхронизации,
чтобы удалённые записи не появлялись вновь. Также могут сохраняться локальные
восстановленные версии конфликтующих профилей; их можно убрать отдельно.
Удаление хоста или отключение синхронизации не является полным удалением всех
метаданных синхронизации. В Farport пока нет команды для очистки всей частной базы CloudKit.

Удаление приложения не обязательно удаляет все скачанные и экспортированные файлы,
системный кэш Finder, записи Связки ключей и резервные копии. Управляйте такими
копиями через соответствующие системные настройки, файловые менеджеры и средства
резервного копирования. Удаление хоста или отключение не удаляет файлы, журналы
и сессии tmux на сервере; ими нужно управлять на самом сервере.

Разработчик не может получить локальные данные приложения, секреты Связки ключей
или частные записи CloudKit через серверную систему Farport. Обращайтесь к нему
с вопросами об управлении данными приложения или об информации, которую вы
отправили непосредственно в поддержку.

### Безопасность

Farport использует SSH для подключений, Связку ключей для данных входа и явную
проверку ключей серверов. Проверяйте отпечатки, защищайте устройства и Аккаунт Apple
и подключайтесь к доверенным серверам. Ни один способ электронного хранения
или сетевой передачи не гарантирует абсолютной безопасности.

### Дети и внешние сервисы

Farport — инструмент для разработчиков общего назначения, не предназначенный
специально для детей. Разработчик не запрашивает персональные данные детей
намеренно. Если вы считаете, что ребёнок отправил персональные данные в поддержку,
свяжитесь с разработчиком для их удаления.

Удалённые серверы, сервисы Apple, приложения для открытия файлов и внешние сайты
имеют собственные правила обработки информации. Ознакомьтесь с политиками
сервисов, которые вы используете вместе с Farport.

### Изменения и контакты

Политика может обновляться при изменении приложения или порядка обработки данных.
В обновлённой версии будет указана новая дата вступления в силу на этой странице.

По вопросам конфиденциальности и обработки обращений пишите **Андрею Пантюхину
(Andrei Pantiukhin)**: [panandafog@icloud.com](mailto:panandafog@icloud.com).
