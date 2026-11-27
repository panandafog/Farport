# SSH commands in Apple Shortcuts

Farport provides the same native App Intents on macOS, iOS and iPadOS. In Apple's
Shortcuts app, add an action and search for **Farport**. No new extension, URL
scheme or password parameter is needed. The actions are localized in English/Russian.

## Actions

- **Run SSH Command / Выполнить SSH-команду**: choose a saved host and enter a
  command or multiline POSIX shell script. Optional fields are Working Directory,
  Standard Input and Timeout. Returns a structured **SSH Command Result** with
  Standard Output, Standard Error, Exit Code, Succeeded, Duration and Host Name.
- **Find Saved Hosts / Найти сохранённые хосты**: filter by name, address or
  username, case-insensitively. An empty filter returns all saved hosts in library
  order. Feed each result into Run SSH Command using **Repeat with Each**.
- **Make Command Result File / Создать файл с результатом команды**: converts a
  result to UTF-8 TXT or JSON for Shortcuts' Save File, Share or other file actions.
  JSON contains `stdout`, `stderr`, `exitCode` and `duration` (seconds).
- **Open Host Settings / Открыть настройки хоста**: opens Farport and the selected
  host's editor, for example after a missing-credentials error. It does not discard
  an already open editor or connect to the server automatically.

The Run action puts command/host in its summary; expand its options to set the
directory, stdin or timeout. The result's individual properties can be selected as
Shortcuts variables. A nonzero exit code is a normal result, so use **If** with
**Succeeded** or **Exit Code** to branch. Transport/trust/credential failures stop
the action with an explanatory error.

## First setup

1. Open Farport on this device and save the host's credentials in Keychain.
2. Connect normally once, reviewing the server fingerprint and granting any Local
   Network permission. Review every ProxyJump endpoint too.
3. Create a shortcut with Run SSH Command, select the host and try `uname -a; uptime`.
4. Add Show Result using the action's Standard Output property.

A host is referenced by its stable UUID. Execution reads its current local saved
configuration, including all jump hosts. Renaming a host keeps the reference;
deleting/recreating it requires choosing the new host. iCloud synchronizes profiles,
not credentials or trusted server keys; set those up separately on each device.

## Useful workflows

- **Health check**: Run `uptime; df -h /` → Show Result, or Show Notification.
- **Several servers**: Find Saved Hosts with filter `staging` → Repeat with Each →
  Run SSH Command on Repeat Item → collect output and host names in a report.
- **JSON status**: run a server command that emits JSON → get Standard Output →
  Shortcuts' Get Dictionary from Input → inspect a field with If.
- **Text processing**: supply text through Standard Input and run `sort | uniq -c`.
  The text is sent as input bytes rather than interpolated into a shell command.
- **Maintenance button**: run a deliberately chosen script, inspect Exit Code,
  then notify or save the result. For privilege checks use noninteractive commands
  such as `sudo -n`; interactive password prompts are unsupported.
- **Report file**: Run SSH Command → Make Command Result File (TXT/JSON) → Save File.
  The destination and any subsequent sharing remain under Shortcuts' control.

Russian action chain example:

**Найти сохранённые хосты** (`staging`) → **Повторить с каждым** →
**Выполнить SSH-команду** (`uptime`, хост — текущий элемент) →
**Если** код завершения равен `0` → **Показать результат** со стандартным выводом.

## Execution contract and limits

Each invocation creates an independent SSH connection/ProxyJump route and a
non-PTY exec channel on the final server. It uses `/bin/sh` and the server account's
default environment/home unless Working Directory is supplied. That directory is
literal (no `~`, `$HOME` or shell expansion). The command itself is a shell script.

It never types into an existing terminal, attaches/creates tmux sessions, changes
their state, or injects Farport's interactive prompt/theme. The host's and tab's
tmux defaults do not affect one-shot commands. Shell aliases, interactive profiles,
working directory and exported variables from another terminal do not carry over.
Use absolute executable paths or set PATH in the script when needed.

- Default timeout: **20 seconds**, including connection/authentication time.
- Maximum timeout: **25 seconds on iPhone/iPad**, **300 seconds on Mac**. iOS may
  interrupt execution; this is not a promise of persistent background SSH.
- Command: up to 64 KiB; directory: 4096 UTF-8 bytes; stdin: 1 MiB; combined
  stdout/stderr: 4 MiB. Text output is decoded as UTF-8; binary transfer is outside
  this action's scope.
- Device authentication is required. Unknown/changed server keys fail closed;
  trust can only be reviewed in Farport. All jump endpoints retain separate pins
  and credentials. These actions do not auto-grant Local Network access.
- **No automatic retry.** A timeout, cancellation, network loss or missing exit
  status may occur after a command has executed. Farport closes its own route;
  that does not guarantee termination of a process on a real remote server.
  Inspect the server before retrying a command with side effects.
- Farport does not store command text, results or a new execution-history database.
  A shortcut and its variables/files can contain sensitive data; use Shortcuts'
  own controls for storage and sharing. Do not embed host passwords in scripts.
- Host lookup is read-only and does not migrate libraries, rotate secrets, create
  workspaces or publish iCloud changes. Old library formats require opening Farport
  first. Demo, screenshot and isolated-test modes cannot access real automation data.

## Implementation and verification

`SharedUI/Automation` owns App Intents/entities and foreground settings navigation.
`FarportCore` owns validated request/result types and read-only library/route lookup.
`FarportSSH.SSHCommandRunner` owns a dedicated connection, bounded collection,
deadline and cancellation. Citadel's documented exec adapter preserves separate
streams and requires an actual SSH exit-status; zero is never invented for EOF.

The disposable AsyncSSH/ProxyJump fixture checks Unicode stdin/EOF, stdout/stderr,
nonzero exit codes, directory quoting, output bounds, unconfirmed exits, host-key
rejection, setup/execution deadlines, cancellation and independent connections.
Both apps compile and embed App Intents metadata plus EN/RU resource tables.
No UI tests or live Shortcuts execution against real hosts were performed. Manual
checks after installing a signed build: action discovery, property selection,
device authentication/Keychain, settings navigation on warm/cold launch, and an
iPhone/iPad shortcut with the app initially closed.
