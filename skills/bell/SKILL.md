---
name: bell
description: Ping the user with a desktop toast and terminal bell every time you finish a meaningful response, so they can step away from the screen while you work. Also fires a Slack/Discord webhook for long-running task completions (build, test, deploy, migration, big refactor — anything ≥30s of wall-clock work). Invoke this at the end of substantive turns; skip it for one-line conversational replies. Trigger phrases also include "알림 켜줘", "끝나면 알려줘", "ping me when done", "notify when ready", "send a finish alert".
---

# bell — 응답 완료 / 작업 완료 알림

This skill exists so the user can run Claude in the background. They walk away from their terminal, you finish your work, the user gets a desktop toast (and a Slack ping for the big stuff) and comes back. Without the ping they have to babysit the terminal.

The underlying tool is `bell-send` (from [bell-bash](https://github.com/tot0rokr/bell-bash)), a standalone bash CLI that fires the same backends as the interactive `bell` function — BEL char to the user's tty, libnotify desktop toast, `noti send` webhook — each in a detached subshell so the call never blocks. Everything happens via the `Bash` tool.

## When to use

Invoke `bell-send` as the **last action of any meaningful response**. "Meaningful" means: you ran tools, edited files, ran tests, answered a non-trivial question. The user planned this skill in *because* they want a signal that the turn is over.

Pick the backend set from the table:

| Situation | Backends | Why |
|---|---|---|
| Default end-of-response ping | `bel,notify-send` | Cheap, local, doesn't spam the team channel. |
| Long-running task done (build / test / deploy / migration / large search, ≥30s wall time) | `bel,notify-send,webhook` | User might have switched contexts entirely — Slack/Discord pulls them back. |
| Failure of a long-running task | `bel,notify-send,webhook` + `--status=<exit>` | `--status` flips notify-send urgency to "critical" so the toast is visually distinct. |
| Short successful answer (≤2 sentences, user clearly watching) | — skip — | Don't ping for trivia. |

## How to use

```bash
# Default — at the end of a substantive turn
bell-send --backends=bel,notify-send "claude done" "<one-line summary>"

# Big task finished successfully
bell-send --backends=bel,notify-send,webhook "build done" "10m12s, exit 0"

# Big task failed
bell-send --backends=bel,notify-send,webhook --status=$rc \
    "tests failed" "3 red, see output"
```

Conventions:

- **Title**: short subject line that fits in a single notification row. "claude done", "build done", "deploy ok", "tests failed".
- **Body**: optional one-liner of context. Keep it under ~80 chars. Examples: "edited 3 files in src/auth", "migrated 12k rows in 4m", "exit 7, last error: timeout".
- **Status**: pass `--status=<nonzero>` whenever the underlying task failed, so the toast goes critical (red on most desktops) and is visually distinct from a success ping.

## When NOT to use

- **Mid-response** — don't ping for intermediate progress. The skill is the closing gesture.
- **Tight loops** — debounce yourself. If you fire `bell-send` three times in one turn the user gets three toasts; consolidate.
- **Trivial replies** — one-sentence "yes, line 42" answers don't need a ping.
- **Webhook for everyday work** — only include `webhook` for genuinely long tasks (≥30s) or when the user explicitly said the work is important. Webhook hits a paid attention channel.
- **User said "no alerts"** — respect explicit user override for the rest of the conversation.

## Prerequisites & failure modes

`bell-send` itself is always safe to call — every backend silently no-ops when its prerequisite is missing:

| Backend | Needs | If missing |
|---|---|---|
| `bel` | A writable `/dev/tty` (else stderr) | Silent — bash error from failed redirection is suppressed |
| `notify-send` | `libnotify-bin` + DBus session | Silent |
| `webhook` | `noti` CLI + `$NOTI_WEBHOOK` exported | Silent |

So you can include all three in `--backends=` without checking — partial environments just get partial alerts. The user installed bell-bash; trust the default. Don't paste `$NOTI_WEBHOOK` back to the user — it's a credential.

## Common patterns

### End-of-turn after editing files

```bash
bell-send --backends=bel,notify-send "claude done" "edited 3 files in src/auth"
```

### End-of-turn after a long build

```bash
# After running `make -j8` (took 6m12s, exit 0):
bell-send --backends=bel,notify-send,webhook "build done" "make -j8, 6m12s, exit 0"
```

### End-of-turn after a failed test run

```bash
# After running tests that failed:
bell-send --backends=bel,notify-send,webhook --status=1 \
    "tests failed" "3 failures in auth_test.go"
```

### End-of-turn for short Q&A

Skip the call entirely. The user is watching the terminal in real time.

## Reading the result

`bell-send` always exits 0 unless arguments were malformed (exit 2). No output on success. Don't poll, don't retry — fire and forget.

## Etiquette

- One `bell-send` per turn, at the very end. Multiple toasts per response is noise.
- Match the channel weight to the work: BEL/toast for "I finished", webhook for "I finished *the big thing*".
- The user's webhook is shared with their team. Don't include sensitive data (tokens, PII, raw logs) in the title or body — summaries only.
- If the user has already moved on (next turn started), don't retroactively send a bell for the previous turn.
