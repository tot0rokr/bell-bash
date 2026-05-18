# bell-bash — long-running command notification system for interactive bash.
# SPDX-License-Identifier: BSD-3-Clause
# See PRD.md for the full spec.
#
# Sourced from ~/.bashrc; no shebang on purpose. Bash 5+ required.

# Bash version guard. EPOCHREALTIME (used by the auto-trigger hook) needs 5.0+.
if [[ -z "${BASH_VERSION:-}" ]] || (( ${BASH_VERSINFO[0]:-0} < 5 )); then
    return 0 2>/dev/null
fi

# Interactive shells only. Non-interactive contexts (agent bash_tool, scripts,
# `bash -c`, `ssh host cmd`) never evaluate this past here, so PS0 /
# PROMPT_COMMAND hooks and the `bell` function are absent there by design.
[[ $- != *i* ]] && return 0

# --- config ----------------------------------------------------------------

: "${BELL_BASH_THRESHOLD:=5}"        # seconds; auto-trigger threshold (float ok)
: "${BELL_BASH_BACKENDS:=bel}"       # comma-separated: bel,notify-send,webhook
: "${BELL_BASH_TIMEOUT_MS:=4000}"    # notify-send toast duration

# --- backends --------------------------------------------------------------

__bell_bash_backend_bel() {
    # Send BEL (0x07) to stderr so it isn't captured by $(...) substitutions.
    # The terminal emulator or tmux's monitor-bell turns this into a visible
    # or audible alert.
    printf '\a' >&2
}

# --- dispatch --------------------------------------------------------------

__bell_bash_dispatch() {
    local exit_code=$1 title=$2 body=$3
    local backend
    local IFS=','
    for backend in $BELL_BASH_BACKENDS; do
        backend=${backend// /}
        [[ -z $backend ]] && continue
        case $backend in
            bel) __bell_bash_backend_bel "$exit_code" "$title" "$body" ;;
            *)   : ;;
        esac
    done
}

# --- explicit trigger: bell ------------------------------------------------
#
# Wrapper:  bell make -j8          → run, alert on its exit, return same code
# Postfix:  cmd1 && cmd2; bell     → alert on the previous command's $?
#
# Always fires regardless of skip-list — an explicit call means the user wants
# the notification.

bell() {
    # Capture $? as the very first thing — any other statement (including
    # the interactivity test below) clobbers it. This matters for postfix
    # mode where the caller relied on the previous command's exit code.
    local __bb_prev=$?
    [[ $- != *i* ]] && return "$__bb_prev"
    local exit_code title body
    local host=${HOSTNAME%%.*}

    if (( $# == 0 )); then
        exit_code=$__bb_prev
        if (( exit_code == 0 )); then
            title="✅ done"
        else
            title="❌ failed (exit ${exit_code})"
        fi
        body=$(printf 'previous command\nhost: %s  cwd: %s' "$host" "$PWD")
        __bell_bash_dispatch "$exit_code" "$title" "$body"
        return "$exit_code"
    fi

    "$@"
    exit_code=$?
    if (( exit_code == 0 )); then
        title="✅ done"
    else
        title="❌ failed (exit ${exit_code})"
    fi
    body=$(printf '%s\nhost: %s  cwd: %s' "$*" "$host" "$PWD")
    __bell_bash_dispatch "$exit_code" "$title" "$body"
    return "$exit_code"
}

# --- auto-trigger ----------------------------------------------------------
#
# A DEBUG trap captures the start time; PROMPT_COMMAND reads it back and fires.
#
# Why not PS0? PS0 expansion runs command substitutions in a subshell, so any
# variable set inside `$(__bell_bash_pre)` is lost. Parameter-substitution
# tricks like `${start:=$EPOCHREALTIME}` survive, but they also *echo* the
# value to the terminal. The DEBUG trap runs in the current shell with no
# stdout side effects, so it's the right tool here.
#
# Pattern (same shape as bash-preexec): an "armed" flag is set at the end of
# PROMPT_COMMAND. The DEBUG trap captures start on the first command after a
# prompt, then disarms — subsequent commands in `cmd1 && cmd2` keep the
# original start time. The trap also skips its own work for tab completion,
# readline editing, and the wrapper-function invocation itself.

__bell_bash_pre_debug() {
    # Skip the PROMPT_COMMAND wrapper call so we don't capture its timing.
    [[ "$BASH_COMMAND" == "__bell_bash_prompt_command"* ]] && return
    # Tab completion / readline pre-edit hooks — not real commands.
    [[ -n "${COMP_LINE:-}" ]] && return
    [[ -n "${READLINE_LINE:-}" ]] && return
    # Not armed yet — happens during shell startup and within a single command.
    [[ -z "${__bell_bash_armed:-}" ]] && return
    __bell_bash_armed=
    __bell_bash_start=$EPOCHREALTIME
}

__bell_bash_post() {
    local exit_code=$1
    [[ -z "${__bell_bash_start:-}" ]] && return 0
    local start=$__bell_bash_start
    unset __bell_bash_start

    local cmd
    cmd=$(HISTTIMEFORMAT='' history 1 2>/dev/null \
          | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+//')

    local elapsed
    elapsed=$(awk -v s="$start" -v e="$EPOCHREALTIME" \
              'BEGIN{ printf "%.2f", e - s }')

    # Float threshold comparison via awk; bash arithmetic is integer-only.
    awk -v e="$elapsed" -v t="$BELL_BASH_THRESHOLD" \
        'BEGIN{ exit !(e + 0 >= t + 0) }' || return 0

    # Skip-list (regex assembled by commit 4; empty here means "no skip").
    if [[ -n "${BELL_BASH_SKIP_REGEX:-}" && "$cmd" =~ $BELL_BASH_SKIP_REGEX ]]; then
        return 0
    fi

    local host=${HOSTNAME%%.*}
    local title body
    if (( exit_code == 0 )); then
        title="✅ done (${elapsed}s)"
    else
        title="❌ failed exit ${exit_code} (${elapsed}s)"
    fi
    body=$(printf '%s\nhost: %s  cwd: %s' "$cmd" "$host" "$PWD")
    __bell_bash_dispatch "$exit_code" "$title" "$body"
}

# Wrap the chain into a function so the DEBUG trap fires only once per prompt
# (DEBUG does not descend into function bodies unless `set -T` is on, which is
# rare). The function call itself is filtered out by name in the DEBUG handler.
__bell_bash_prompt_command() {
    local exit_code=$?
    # Restore $? before running the previous PROMPT_COMMAND so cooperative
    # hooks like starship's status indicator see the user's actual exit code.
    if [[ -n "${__bell_bash_prev_pc:-}" ]]; then
        (exit "$exit_code")
        eval "$__bell_bash_prev_pc"
    fi
    __bell_bash_post "$exit_code"
    # Re-arm so the DEBUG trap captures the next user command's start time.
    __bell_bash_armed=on
    return "$exit_code"
}

# Idempotent install — re-sourcing must not chain hooks twice.
if [[ "${PROMPT_COMMAND:-}" != *"__bell_bash_prompt_command"* ]]; then
    __bell_bash_prev_pc=${PROMPT_COMMAND:-}
    PROMPT_COMMAND='__bell_bash_prompt_command'
fi

# Install DEBUG trap. Existing DEBUG traps are clobbered; chaining with other
# bash-preexec-style libraries is future work.
trap '__bell_bash_pre_debug' DEBUG
