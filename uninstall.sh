#!/usr/bin/env bash
# Removes everything install.sh created. Usage: ./uninstall.sh [--purge]  (--purge also deletes saved sessions list)
set -euo pipefail
prefix=${PREFIX:-$HOME/.local}
if command -v systemctl > /dev/null 2>&1 && systemctl --user show-environment > /dev/null 2>&1; then
  systemctl --user disable --now claude-session-save.timer 2> /dev/null || true
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/claude-session-save."{service,timer}
  systemctl --user daemon-reload || true
fi
if command -v crontab > /dev/null 2>&1 && crontab -l 2> /dev/null | grep -qF '# claude-session-restore'; then
  crontab -l | grep -vF '# claude-session-restore' | crontab -
fi
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/claude-session-restore.desktop"
for f in claude-save-session claude-restore-session claude-session-tab; do rm -f "$prefix/bin/$f"; done
rm -rf "$prefix/lib/claude-session-restore"
if [[ ${1:-} == --purge ]]; then rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/claude-session-restore"; fi
echo "uninstalled"
