# Session-local accent prompt

In Terminal Appearance, **Use App Accent** controls SSH prompts, tmux status/copy-mode
panels, cursor and selection together. The setting is device-local, on by default,
and shared by all hosts on that device. macOS exposes
it through Terminal > Terminal Appearance / Settings; iOS through Terminal Actions >
Terminal Appearance. It does not change host profiles, credentials or iCloud records.

Prompt styling applies when a new shell starts. Reconnect Standard SSH. For tmux, open
a new terminal tab: attaching to an existing UUID session keeps its processes and
prompt. Switching this option, system appearance or accent does not inject commands
into a running shell or restart it. Tmux panels and native cursor/selection update
immediately; turning the setting off removes the UUID session/window style overrides
so tmux inherits its server defaults. A new shell receives the currently resolved
application accent, independently of ANSI palette roles. Shell output such as `ls`,
Git and logs keeps the colors sent by the server.

## Supported environment

Unix servers with Bash or Zsh as `$SHELL`, `/bin/sh`, `mktemp`, `cat`, `rm` and `rmdir`.
The account needs access to a writable temporary directory. This is shell integration,
not a universal SSH feature. Keep it disabled for limited/custom SSH servers such as
Rebex, Windows shells, forced-command accounts and servers that disallow command execution.
Unsupported Unix shells or failure to create a private directory print a notice and
start the account's login shell. SSH authentication/host-key rules are unchanged.

## Startup and cleanup

The SSH adapter wraps the new shell in a small `/bin/sh` launcher. With tmux the
launcher is passed as the new-session command and runs only if tmux creates that
session. It never uses `send-keys` or the interactive input queue for setup.

The launcher creates a mode-700 `farport-shell.XXXXXXXX` directory under remote
`$TMPDIR` (or `/tmp`), with private startup shims. It restores the original umask
before starting the user's shell. A parent process removes only the known helper
files and that empty directory when the shell ends. Helpers stay while a tmux shell
is alive; detach is not shell exit. Abrupt server shutdown/SIGKILL can leave a small
temporary directory for the server's usual temporary-file cleanup. Nothing is
installed into the account's home, and `.bashrc`/`.zshrc` files are not rewritten.

Bash uses an interactive `--rcfile` shell. Its shim reads `/etc/profile` and the first
readable `.bash_profile`, `.bash_login` or `.profile`, then appends a prompt function
after the existing string/array PROMPT_COMMAND. This preserves ordinary profile-based
aliases/functions but is not a native login-shell flag; advanced login-only logic
and logout behavior can differ. Do not enable the option when exact custom startup
semantics are required.

Zsh starts as an interactive login shell. Temporary ZDOTDIR shims source the account's
`.zshenv`, `.zprofile`, `.zshrc` and `.zlogin` in order, respecting changes to the
account's own ZDOTDIR, then restore it.
System profile/rc/login files are sourced explicitly with the user's directory as
well; GLOBAL_RCS is temporarily suppressed between shims and restored afterwards.
This keeps the system's history/cache paths out of the private helper directory.
Global-file lookup covers `/etc`, `/etc/zsh` and the shell installation's `etc`
or `etc/zsh` directory; builds with a custom global configuration location need
the option disabled.
An appended `precmd_functions` hook supplies
the prompt and clears the right prompt. Custom system startup code which overrides
ZDOTDIR or disables RCS, read-only prompt variables and third-party prompt frameworks
can prevent integration; disable the option for those configurations.

The supplied prompt is `user@host:path` with Bash/Zsh-native prompt escapes for correct
cursor width. Existing prompt hooks still run; the Farport hook runs last. Later shell
customization can replace it. The feature intentionally chooses its own prompt layout.

Startup references: [Bash startup files](https://www.gnu.org/software/bash/manual/html_node/Bash-Startup-Files),
[Zsh startup files](https://zsh.sourceforge.io/Doc/Release/Files.html).

## Verification

`swift test --filter ShellPromptTests` runs disposable local PTYs through
`Scripts/prompt_fixture.py`. The fixture uses temporary homes/TMPDIR and does not
connect to real servers or run UI automation. Tests cover profile/hook preservation,
custom ZDOTDIR, true-color prompt output, unchanged ANSI output, quotation of paths,
helper cleanup and opt-out command compatibility. Ordinary tmux discovery tests
remain part of the SSH test suite.
