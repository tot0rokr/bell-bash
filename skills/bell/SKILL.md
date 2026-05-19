---
name: bell
description: Send an explicit notification via `bell-send` (terminal BEL + desktop toast + optional Slack/Discord webhook). Use for long-running task completions (build, test, deploy, migration, big refactor — anything ≥30s of wall-clock work) or to flag a failure with critical urgency. Default end-of-turn pings are handled by a Stop hook, so don't invoke this just to mark "I'm done" — only when the notification needs a webhook, a non-zero status, or a custom title/body. Trigger phrases include "알림 켜줘", "끝나면 알려줘", "ping me when done", "notify when ready", "send a finish alert".
---

# bell — 명시적 작업 완료 알림

기본적인 응답 종료 알림은 Stop hook이 처리한다. 이 skill은 hook이 보낼 수 없는 알림 — 장시간 작업 완료(Slack/Discord webhook 포함), 실패 신호(`--status`로 critical urgency), 또는 사용자가 명시적으로 요청한 커스텀 제목/본문 — 을 보낼 때 호출한다.

The underlying tool is `bell-send` (from [bell-bash](https://github.com/tot0rokr/bell-bash)), a standalone bash CLI that fires the same backends as the interactive `bell` function — BEL char to the user's tty, libnotify desktop toast, `noti send` webhook — each in a detached subshell so the call never blocks. Everything happens via the `Bash` tool.

## When to use

| Situation | Backends | Why |
|---|---|---|
| Long-running task done (build / test / deploy / migration / large search, ≥30s wall time) | `bel,notify-send,webhook` | User might have switched contexts entirely — Slack/Discord pulls them back. |
| Failure of a long-running task | `bel,notify-send,webhook` + `--status=<exit>` | `--status` flips notify-send urgency to "critical" so the toast is visually distinct. |
| User explicitly asked for a custom alert ("ping me when X finishes") | varies — match the user's request | They asked for it. |

For ordinary end-of-turn pings, do nothing — the hook handles it.

## How to use

```bash
# Big task finished successfully
bell-send --backends=bel,notify-send,webhook "build done" "10m12s, exit 0"

# Big task failed
bell-send --backends=bel,notify-send,webhook --status=$rc \
    "tests failed" "3 red, see output"
```

Conventions:

- **Title**: short subject line that fits in a single notification row. "build done", "deploy ok", "tests failed".
- **Body**: optional one-liner of context. Keep it under ~80 chars. Examples: "migrated 12k rows in 4m", "exit 7, last error: timeout".
- **Status**: pass `--status=<nonzero>` whenever the underlying task failed, so the toast goes critical (red on most desktops) and is visually distinct from a success ping.

## When NOT to use

- **Default end-of-turn ping** — that's the Stop hook's job. Calling `bell-send` here would double up.
- **Mid-response progress** — don't ping for intermediate steps.
- **Tight loops** — debounce yourself. If you fire `bell-send` three times in one turn the user gets three toasts; consolidate.
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

### After a long build completes

```bash
# After running `make -j8` (took 6m12s, exit 0):
bell-send --backends=bel,notify-send,webhook "build done" "make -j8, 6m12s, exit 0"
```

### After a failed test run

```bash
# After running tests that failed:
bell-send --backends=bel,notify-send,webhook --status=1 \
    "tests failed" "3 failures in auth_test.go"
```

## Reading the result

`bell-send` always exits 0 unless arguments were malformed (exit 2). No output on success. Don't poll, don't retry — fire and forget.

## Etiquette

- Don't duplicate the hook. If the only thing you'd say is "I'm done", say nothing — the Stop hook already pinged.
- Match the channel weight to the work: BEL/toast for "I finished", webhook for "I finished *the big thing*".
- The user's webhook is shared with their team. Don't include sensitive data (tokens, PII, raw logs) in the title or body — summaries only.
