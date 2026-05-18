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
