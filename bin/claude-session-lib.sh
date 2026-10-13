# shellcheck shell=bash
# Shared helpers for claude-session-restore. Meant to be sourced, never executed.

CSR_ID_RE='^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'

csr_claude_dir() { printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }
csr_state_dir() { printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/claude-session-restore"; }
csr_state_file() { printf '%s/sessions.tsv' "$(csr_state_dir)"; }

# A session id is a UUID. Anything else is rejected, so ids are safe to pass as arguments.
csr_valid_id() { [[ $1 =~ $CSR_ID_RE ]]; }

# A cwd must be an absolute path without control characters (tabs/newlines would corrupt the TSV).
csr_valid_cwd() { [[ $1 == /* && $1 != *[[:cntrl:]]* ]]; }

# Prints "<start-time>\t<session-id>\t<cwd>" for every interactive Claude Code
# process owned by the current user. Never reads transcripts or credentials:
# only ~/.claude/sessions/<pid>.json is consulted, and only for "sessionId".
csr_running_sessions() {
  local proc pid comm stat rest start cwd id json args a skip kind
  local -a fields
  local name=${CLAUDE_PROCESS_NAME:-claude}
  local sdir
  sdir="$(csr_claude_dir)/sessions"
  for proc in /proc/[0-9]*; do
    pid=${proc#/proc/}
    [[ -O $proc ]] || continue
    IFS= read -r comm < "$proc/comm" 2>/dev/null || continue
    [[ $comm == "$name" ]] || continue
    cwd=$(readlink "$proc/cwd" 2>/dev/null) || continue
    csr_valid_cwd "$cwd" || continue
    mapfile -d '' -t args < "$proc/cmdline" 2>/dev/null || continue
    skip=0
    for a in "${args[@]}"; do
      case $a in -p | --print) skip=1 ;; esac
    done
    ((skip)) && continue
    stat=$(< "$proc/stat") || continue
    rest=${stat##*) }
    read -r -a fields <<< "$rest"
    start=${fields[19]:-0}
    id=
    json="$sdir/$pid.json"
    if [[ -f $json ]]; then
      kind=$(grep -o '"kind" *: *"[^"]*"' "$json" 2>/dev/null | head -n1 | cut -d'"' -f4)
      [[ -z $kind || $kind == interactive ]] || continue
      id=$(grep -o '"sessionId" *: *"[^"]*"' "$json" 2>/dev/null | head -n1 | cut -d'"' -f4)
    fi
    if ! csr_valid_id "$id"; then
      id=
      local i
      for ((i = 0; i < ${#args[@]} - 1; i++)); do
        if [[ ${args[i]} == --resume || ${args[i]} == -r ]]; then
          id=${args[i + 1]}
          break
        fi
      done
    fi
    csr_valid_id "$id" || continue
    printf '%s\t%s\t%s\n' "$start" "$id" "$cwd"
  done
}
