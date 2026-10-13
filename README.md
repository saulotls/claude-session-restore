# claude-session-restore

Reopen your [Claude Code](https://claude.com/claude-code) sessions after a reboot, shutdown or crash — one terminal tab per session, each one resumed with `claude --resume <id>` in its original directory.

> Unofficial community tool, not affiliated with Anthropic. Linux only (it reads `/proc`).

## How it works

- **Save:** `claude-save-session` looks at the interactive `claude` processes you are running and records `session-id<TAB>directory` in `~/.local/state/claude-session-restore/sessions.tsv`. A systemd user timer (or a cron entry) runs it every minute, so after a power-off the list is at most one minute old. It never overwrites the list with an empty one, and keeps the previous version in `sessions.tsv.prev`.
- **Restore:** `claude-restore-session` reads that list and opens one tab per session. It runs automatically at login through an XDG autostart entry (8 s delay) and skips sessions that are already running, so running it twice never duplicates tabs.
- The conversation itself is untouched: Claude Code keeps transcripts under `~/.claude/projects`; this tool only remembers *which* ones were open.

## Install

```bash
git clone https://github.com/saulotls/claude-session-restore.git
cd claude-session-restore
./install.sh                 # --no-autostart / --no-timer to skip parts
```

Installs to `~/.local/bin` (override with `PREFIX=...`), no root needed. Make sure `~/.local/bin` is in your `PATH`.

Uninstall with `./uninstall.sh` (`--purge` also deletes the saved list).

## Usage

```bash
claude-save-session                       # save now
claude-restore-session                    # restore now
claude-restore-session --dry-run          # show what would be launched
claude-restore-session --terminal tmux    # force a terminal / multiplexer
```

Supported: `konsole`, `gnome-terminal`, `xfce4-terminal`, `kitty` (one window with tabs), `tmux` (session `claude`; good for SSH/headless), and one window per session for `alacritty`, `foot`, `wezterm`, `xterm`, `x-terminal-emulator`. Anything else: `CLAUDE_RESTORE_TERMINAL_CMD="myterm -e" claude-restore-session`.

Environment variables: `CLAUDE_CONFIG_DIR` (default `~/.claude`), `XDG_STATE_HOME`, `CLAUDE_RESTORE_TERMINAL`, `CLAUDE_RESTORE_TERMINAL_CMD`, `CLAUDE_BIN`, `CLAUDE_PROCESS_NAME` (default `claude`).

Tested on KDE Konsole. The other terminals are covered by command-construction tests only; please open an issue if one misbehaves.

## Limitations

- **Shutdown is not hooked.** Processes are already dying at that point, so a "save on shutdown" could store a partial list. The one-minute timer avoids that. If you close all Claude sessions on purpose and then shut down, the last non-empty list is kept and restored next time.
- Only interactive sessions are saved (`claude -p ...` is ignored).
- Claude must run as a process named `claude` (native installer or npm launcher). Otherwise set `CLAUDE_PROCESS_NAME`.

## Security notes

- No network access, no root, no `eval`. Files are created with mode `0600` (state dir `0700`).
- It reads one field (`sessionId`, plus `kind`) from `~/.claude/sessions/<pid>.json`. It never reads transcripts, credentials, or the `.key` files next to them.
- The saved list is treated as untrusted input on restore: session ids must be UUIDs, directories must be absolute paths without control characters, and nothing from the list is ever interpolated into a shell command — ids are passed as plain arguments to a fixed launcher (`claude-session-tab`), which looks the directory up itself.
- Install paths are restricted to `[A-Za-z0-9_./+@%-]` because they are embedded in terminal command lines.
- Run the checks yourself: `shellcheck -x -P SCRIPTDIR bin/* *.sh tests/run.sh && bash tests/run.sh` (tests use a fake `$HOME`, fake processes and fake terminals).

## Português

Reabre suas sessões do Claude Code após reiniciar ou desligar o computador: uma aba de terminal por sessão, cada uma com `claude --resume <id>` na pasta original. Um timer do systemd salva a lista a cada minuto e o autostart do login restaura tudo. Instalação: `./install.sh`. Desinstalação: `./uninstall.sh`. O desligamento em si não é interceptado (os processos já estão sendo encerrados); por isso o salvamento é periódico.

## License

MIT
