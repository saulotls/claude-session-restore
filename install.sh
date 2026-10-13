#!/usr/bin/env bash
# Installs claude-session-restore for the current user. No root, no network.
# Usage: ./install.sh [--no-autostart] [--no-timer]
# Env:   PREFIX (default ~/.local)
set -euo pipefail

autostart=1 timer=1
for a in "$@"; do
  case $a in
    --no-autostart) autostart=0 ;;
    --no-timer) timer=0 ;;
    -h | --help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

[[ $(uname -s) == Linux ]] || { echo "Linux only (needs /proc)" >&2; exit 1; }
[[ $EUID -ne 0 ]] || { echo "do not run as root; this is a per-user tool" >&2; exit 1; }

src=$(dirname "$(readlink -f "$0")")
prefix=${PREFIX:-$HOME/.local}
libdir="$prefix/lib/claude-session-restore"
bindir="$prefix/bin"
for p in "$libdir" "$bindir"; do
  [[ $p =~ ^/[A-Za-z0-9_./+@%-]+$ ]] || { echo "unsupported characters in path: $p" >&2; exit 1; }
done

mkdir -p "$libdir" "$bindir"
install -m 0644 "$src/bin/claude-session-lib.sh" "$libdir/"
for f in claude-save-session claude-restore-session claude-session-tab; do
  install -m 0755 "$src/bin/$f" "$libdir/$f"
  ln -sfn "$libdir/$f" "$bindir/$f"
done
echo "installed commands in $bindir"
case ":$PATH:" in *":$bindir:"*) ;; *) echo "note: $bindir is not in your PATH" ;; esac

if ((autostart)); then
  ad="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
  mkdir -p "$ad"
  cat > "$ad/claude-session-restore.desktop" << EOD
[Desktop Entry]
Type=Application
Name=Restore Claude Code sessions
Exec=$bindir/claude-restore-session --delay 8
Terminal=false
X-GNOME-Autostart-enabled=true
EOD
  echo "autostart entry: $ad/claude-session-restore.desktop"
fi

if ((timer)); then
  if command -v systemctl > /dev/null 2>&1 && systemctl --user show-environment > /dev/null 2>&1; then
    ud="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    mkdir -p "$ud"
    {
      printf '[Unit]\nDescription=Save running Claude Code sessions\n\n[Service]\nType=oneshot\n'
      if [[ -n ${CLAUDE_CONFIG_DIR:-} && $CLAUDE_CONFIG_DIR =~ ^/[A-Za-z0-9_./+@%-]+$ ]]; then
        printf 'Environment=CLAUDE_CONFIG_DIR=%s\n' "$CLAUDE_CONFIG_DIR"
      fi
      printf 'ExecStart=%s/claude-save-session\n' "$bindir"
    } > "$ud/claude-session-save.service"
    # OnActiveSec (not OnStartupSec): the first run happens 3 min after the timer
    # starts, so enabling it never saves a half-empty list before sessions are restored.
    cat > "$ud/claude-session-save.timer" << 'EOD'
[Unit]
Description=Save running Claude Code sessions every minute

[Timer]
OnActiveSec=3min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOD
    systemctl --user daemon-reload
    systemctl --user enable --now claude-session-save.timer
    echo "systemd user timer enabled (claude-session-save.timer)"
  elif command -v crontab > /dev/null 2>&1; then
    line="* * * * * $bindir/claude-save-session # claude-session-restore"
    { crontab -l 2> /dev/null | grep -vF '# claude-session-restore' || true; echo "$line"; } | crontab -
    echo "cron entry added"
  else
    echo "no systemd or cron found: run claude-save-session periodically yourself" >&2
  fi
fi
echo "done. Test: claude-save-session && cat \"\${XDG_STATE_HOME:-\$HOME/.local/state}/claude-session-restore/sessions.tsv\""
