#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # test snippets are intentionally single-quoted and eval-ed
# Self-contained tests: fake HOME, fake `claude` processes and fake terminals. Touches nothing real.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
export HOME="$T/home" XDG_STATE_HOME="$T/home/.local/state" XDG_CONFIG_HOME="$T/home/.config"
export CLAUDE_CONFIG_DIR="$T/home/.claude" PATH="$T/fakebin:$PATH" CLAUDE_PROCESS_NAME=claude-fake  # keeps real claude processes out of the scan
unset DISPLAY WAYLAND_DISPLAY
mkdir -p "$HOME/proj a" "$CLAUDE_CONFIG_DIR/sessions" "$T/fakebin"
state="$XDG_STATE_HOME/claude-session-restore/sessions.tsv"
pass=0 fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); echo "ok   - $1"; else fail=$((fail + 1)); echo "FAIL - $1"; fi; }

# fake claude: a script named "claude" gets comm=claude
printf '#!/bin/bash\nsleep 60\n' > "$T/fakebin/claude-fake"; chmod +x "$T/fakebin/claude-fake"
A=11111111-1111-4111-8111-111111111111
B=22222222-2222-4222-8222-222222222222
C=33333333-3333-4333-8333-333333333333
D=44444444-4444-4444-8444-444444444444

(cd "$HOME/proj a" && exec "$T/fakebin/claude-fake" --resume $A) & pa=$!
(cd "$HOME" && exec "$T/fakebin/claude-fake" --resume $B) & pb=$!
(cd "$HOME" && exec "$T/fakebin/claude-fake" -p hello --resume $C) & pc=$!   # non-interactive: ignored
sleep 1
printf '{"pid":%d,"sessionId":"%s","cwd":"%s","kind":"interactive"}' "$pb" "$D" "$HOME" > "$CLAUDE_CONFIG_DIR/sessions/$pb.json"

"$root/bin/claude-save-session"
ok "state file created with mode 600" '[[ $(stat -c %a "$state") == 600 ]]'
ok "resume id taken from cmdline" 'grep -q "^$A	$HOME/proj a$" "$state"'
ok "json sessionId wins over cmdline" 'grep -q "^$D	" "$state" && ! grep -q "^$B" "$state"'
ok "non-interactive (-p) ignored" '! grep -q "^$C" "$state"'
ok "two sessions saved" '[[ $(wc -l < "$state") == 2 ]]'

cp "$state" "$T/before"
kill $pa $pb $pc; wait 2>/dev/null; sleep 0.5
"$root/bin/claude-save-session"
ok "empty scan keeps previous list" 'cmp -s "$state" "$T/before"'

# restore: tampered / malicious entries
printf '%s\t%s\n' "$A" "$HOME/proj a" "$B" "/nonexistent/dir" "not-a-uuid; rm -rf ~" "/x" \
  "$C" "relative/dir" "$D" "/tmp/evil;;command: touch $T/pwned" > "$state"
printf '%s\t%s\n' "$A\$(touch $T/pwned2)" "$HOME" >> "$state"
out=$("$root/bin/claude-restore-session" --terminal tmux --dry-run 2>&1)
ok "valid ids restored" 'grep -q "new-session.*$A" <<<"$out" && grep -q "new-window.*$B" <<<"$out"'
ok "invalid id rejected" '! grep -q "not-a-uuid" <<<"$out"'
ok "relative cwd rejected" '! grep -q "$C" <<<"$out" || grep -q "skipping $C" <<<"$out"'
ok "injection attempt not executed" '[[ ! -e $T/pwned && ! -e $T/pwned2 ]]'

out=$("$root/bin/claude-restore-session" --terminal nonexistent-term --dry-run 2>&1); rc=$?
ok "missing terminal reported" '[[ $rc != 0 ]] && grep -q "terminal not found" <<<"$out"'
printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/konsole"; chmod +x "$T/fakebin/konsole"
out=$("$root/bin/claude-restore-session" --terminal konsole --dry-run 2>&1)
ok "konsole tabs file format" 'grep -q "^title: claude 1 ;; command: .*claude-session-tab $A$" <<<"$out"'
for t in gnome-terminal xfce4-terminal kitty alacritty; do printf '#!/bin/sh\nexit 0\n' > "$T/fakebin/$t"; chmod +x "$T/fakebin/$t"; done
for t in gnome-terminal xfce4-terminal kitty alacritty; do
  out=$("$root/bin/claude-restore-session" --terminal $t --dry-run 2>&1)
  ok "$t command built" 'grep -q "$A" <<<"$out"'
done
out=$(CLAUDE_RESTORE_TERMINAL_CMD="myterm -e" "$root/bin/claude-restore-session" --dry-run 2>&1)
ok "custom terminal command" 'grep -q "DRY-RUN: setsid myterm -e\|DRY-RUN: myterm -e" <<<"$out"'
ok "bad --terminal rejected" '! "$root/bin/claude-restore-session" --terminal "x;y" --dry-run >/dev/null 2>&1'
ok "bad --delay rejected" '! "$root/bin/claude-restore-session" --delay abc --dry-run >/dev/null 2>&1'

# already-running sessions are skipped
printf '%s\t%s\n' "$A" "$HOME" > "$state"
(cd "$HOME" && exec "$T/fakebin/claude-fake" --resume $A) & p2=$!
sleep 1
out=$("$root/bin/claude-restore-session" --terminal tmux --dry-run 2>&1)
ok "running session not duplicated" 'grep -q "already running" <<<"$out" && ! grep -q "DRY-RUN" <<<"$out"'
kill $p2

# tab script validation
ok "tab rejects bad id" '! "$root/bin/claude-session-tab" "../etc/passwd" 2>/dev/null'
printf '%s\t%s\n' "$A" "$HOME/proj a" > "$state"
printf '#!/bin/bash\npwd > "%s/tabpwd"\necho "$@" > "%s/tabargs"\n' "$T" "$T" > "$T/fakebin/claude"; chmod +x "$T/fakebin/claude"
out=$(SHELL=/bin/true "$root/bin/claude-session-tab" "$A")
ok "tab cds to saved dir" '[[ $(cat "$T/tabpwd") == "$HOME/proj a" ]]'
ok "tab runs claude --resume id" '[[ $(cat "$T/tabargs") == "--resume $A" ]]'

# install / uninstall into a temp prefix
PREFIX="$T/pfx" "$root/install.sh" --no-timer >/dev/null
ok "install creates symlinks" '[[ -x $T/pfx/bin/claude-save-session && -L $T/pfx/bin/claude-restore-session ]]'
ok "autostart uses absolute path" 'grep -q "^Exec=$T/pfx/bin/claude-restore-session --delay 8$" "$XDG_CONFIG_HOME/autostart/claude-session-restore.desktop"'
ok "installed copy works" '"$T/pfx/bin/claude-restore-session" --terminal tmux --dry-run >/dev/null 2>&1'
PREFIX="$T/pfx" "$root/uninstall.sh" >/dev/null
ok "uninstall removes files" '[[ ! -e $T/pfx/bin/claude-save-session && ! -e $T/pfx/lib/claude-session-restore ]]'
ok "uninstall keeps state" '[[ -f $state ]]'

echo "$pass passed, $fail failed"
[[ $fail == 0 ]]
