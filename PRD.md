# PRD — `bell-bash`

긴 명령이 끝났을 때 즉시 인지할 수 있게 해주는 bash 훅 + `bell` 함수 시스템.

| 항목 | 값 |
|---|---|
| Feature name | `bell-bash` |
| Version | 0.1 |
| Status | Spec for implementation |
| Target platform | Linux (Ubuntu 24.04 primary), bash ≥ 5.0 |
| Implementation context | 단독 개발 (Claude Code CLI에서 진행), `tot0rokr/noti-bash`의 `noti` CLI는 *선택적* webhook backend로 연동 |

---

## 1. 요약

`bell-bash`는 **의존성 0의 default로 동작하는** 명령 완료 알림 시스템이다. interactive bash에서 사용자가 직접 친 명령이 (a) 임계값(기본 5s) 이상 걸리거나 (b) 명시적으로 `bell` 함수로 wrapping된 경우, 등록된 backend들로 알림을 발사한다.

기본 backend는 **BEL¹ 단독**(의존성 0). desktop toast(`notify-send`)와 webhook(`noti send`)은 **plugin backend**로 추가 enable한다. tmux와 연동 시 visual bell + status line 메시지 + window flag로 시각 알림이 강화된다. `install.sh`가 `.bashrc`와 `.tmux.conf`를 fzf 스타일로 idempotent²하게 통합한다.

> ¹ BEL (Bell Character, ASCII 0x07): 터미널에 알림을 발생시키는 제어 문자. tmux의 `monitor-bell`이나 터미널 에뮬레이터가 이를 받아 시각/청각 알림으로 변환한다.
>
> ² idempotent: 같은 작업을 여러 번 수행해도 한 번 수행한 것과 결과가 동일한 성질. installer 재실행 시 설정 파일에 동일 내용이 누적되지 않는다.

---

## 2. 배경

기존 `noti-bash`는 webhook 통합 CLI로, 호출이 명시적(`noti send`, `noti run --`)이고 webhook 인프라(URL, 네트워크)를 전제한다. 이는 다음 use case에 부적합하다.

- 로컬에서 빌드/테스트 작업 중인 BSP³ 개발자가 단순히 "빌드 끝났음"을 인지하고 싶을 때
- 에어갭/사내망에서 webhook이 안 닿는 환경
- ad-hoc 명령마다 `noti run --` 을 붙이기 번거로운 경우

`bell-bash`는 이 격차를 메운다.

> ³ BSP (Board Support Package): 특정 하드웨어 보드/플랫폼에서 OS·드라이버·펌웨어가 동작하도록 지원하는 저수준 소프트웨어 계층. 빌드 시간이 길어 완료 알림이 특히 유용하다.

---

## 3. 문제 정의

> 로컬 작업 중인 개발자가 긴 빌드/테스트가 끝났을 때 별도 인프라 없이 즉시 인지할 수 있어야 하며, 환경이 갖춰지면 점진적으로 더 풍부한 알림(desktop toast, webhook)이 추가되어야 한다. 자기 손으로 친 명령에만 알림이 와야 하고, 에이전트/스크립트의 명령은 잡혀선 안 된다.

---

## 4. 목표 / 비목표

### Goals

| ID | 목표 |
|---|---|
| G1 | 의존성 0의 default 동작 (BEL 단독) |
| G2 | 자동 trigger (≥ threshold) + 명시 trigger (`bell`) 모두 지원 |
| G3 | Backend 시스템: BEL / notify-send / webhook을 조합 가능 |
| G4 | 에이전트/스크립트 명령은 별도 감지 없이 자동 제외 |
| G5 | Skip-list로 인터랙티브 프로그램 제외, 런타임 동적 추가/제거 |
| G6 | fzf 스타일 `install.sh`: 대화형 + 비대화형, idempotent, uninstallable |
| G7 | 기존 `.bashrc` / `.tmux.conf` 보존: 자동 백업, 충돌 검사, 마커 기반 in-place 갱신 |
| G8 | tmux 통합: monitor-bell + visual-bell + bell-action + window status flag |

### Non-Goals (v0.1)

| ID | 비목표 | 사유 |
|---|---|---|
| NG1 | 백그라운드 job (`cmd &`) 완료 알림 | 별도 메커니즘 필요; future work |
| NG2 | zsh / fish 지원 | future work |
| NG3 | 명령별 다른 threshold | future work |
| NG4 | webhook의 rich embed 카드 | v1은 plain text only |
| NG5 | 원격(`ssh host`)으로의 자동 알림 전파 | 원격에 별도 설치 필요 |
| NG6 | macOS 지원 | future work (`terminal-notifier`) |

---

## 5. User Stories

- **US1**. BSP 개발자가 빌드 돌리고 자리를 비울 때, 종료 시 tmux status line + window flag로 즉시 인지 (BEL backend만으로).
- **US2**. GUI 데스크톱이면 notify-send 토스트도 자동 수신.
- **US3**. Slack에도 보내고 싶으면 install 시 webhook backend 추가.
- **US4**. `vim`, `tmux`, `ssh`, `top` 같은 인터랙티브 프로그램에는 알림 없음.
- **US5**. 새 long-running 도구(예: `tig`)를 발견하면 `bell_skip += tig`로 즉시 추가.
- **US6**. Claude Code 같은 에이전트의 `bash_tool`이 실행한 명령은 webhook을 울리지 않음.
- **US7**. 명시적으로 알림 받고 싶은 명령은 `bell make -j8`로 wrapping.
- **US8**. `bell make && bell ./test` 처럼 chain 가능 (exit code 그대로 반환).
- **US9**. installer가 기존 `.tmux.conf`에서 `monitor-bell off` 같은 충돌 발견 시, 사용자에게 정리할지 묻고 거절하면 그대로 두기.

---

## 6. 기능 요구사항 (Functional Requirements)

### FR-1. 자동 trigger
사용자가 친 명령의 wall-clock 경과를 `$EPOCHREALTIME`⁴ (bash 5+)로 측정해, `BELL_BASH_THRESHOLD`(기본 `5`, float 허용) 이상이면 알림 발사. 측정은 `PS0`⁵ / `PROMPT_COMMAND`⁶ 훅 페어로 수행.

> ⁴ `$EPOCHREALTIME`: bash 5.0+ 제공. epoch 이후 경과를 `초.마이크로초` 부동소수 문자열로 반환. e.g. `1715000000.123456`. sub-second 측정용.
>
> ⁵ `PS0`: bash 4.4+ 제공. 사용자가 enter를 친 시점, 명령이 실행되기 *직전*에 평가되는 prompt string. side effect용 hook으로 활용 가능.
>
> ⁶ `PROMPT_COMMAND`: 매 prompt 그리기 직전 (이전 명령 완료 후) 평가되는 bash 명령 문자열. 다중 hook을 chain할 때 기존 값 보존 필요.

### FR-2. 명시 trigger
`bell` 함수가 두 모드 지원.

| 모드 | 예 | 동작 |
|---|---|---|
| Wrapper | `bell make -j8` | 인자 명령 실행, 그 exit code로 알림. exit code 그대로 반환 (`&&`/`\|\|` 체인 가능) |
| Postfix | `cmd1 && cmd2; bell` | 직전 명령의 `$?` 캡처해 알림. 라벨 "previous command" |

`bell`는 skip-list와 무관하게 항상 발사 (명시 호출은 사용자가 알림을 *원하는* 것).

### FR-3. Backend 시스템
`BELL_BASH_BACKENDS` (콤마 분리, 기본 `bel`)에 따라 enabled backend들을 모두 호출. 미충족 backend는 silent no-op.

> 명명 주의: 사용자 함수 `bell()`(섹션 FR-2)과 backend 식별자 `bel`은 한 글자 차이지만 역할이 다르다. `bell`은 사용자가 직접 호출하는 함수, `bel`은 환경변수 `BELL_BASH_BACKENDS=bel,...` 안에서만 등장하는 내부 식별자(BEL 제어 문자 0x07의 약어).

| Backend | 의존성 | 동작 |
|---|---|---|
| `bel` | 없음 | `printf '\a' >&2` — tmux의 `monitor-bell` 또는 터미널 에뮬레이터가 처리. **stderr로 보내야** command substitution(`$(...)`)에 캡처되지 않음. |
| `notify-send` | `libnotify-bin` + GUI 세션 | 데스크톱 토스트. 실패 시 `urgency=critical`. background detached (`&` + `disown`). |
| `webhook` | `noti` CLI + `NOTI_WEBHOOK` env | `noti send "<title> — <body>"` 호출. background detached. |

각 backend는 prerequisite 미충족 시 silent return. `webhook`을 `BACKENDS`에 넣어둔 채 `NOTI_WEBHOOK` 없는 환경에서도 에러 없이 다른 backend는 정상 작동해야 한다.

### FR-4. Skip-list (자동 trigger 전용)
인터랙티브 프로그램은 default skip-list에 포함되어 자동 trigger에서 제외. 명시 `bell`는 영향받지 않음. Default 목록:

```
editors:        vi vim nvim emacs nano
pagers:         less more man tail journalctl
remote/mux:     ssh mosh tmux screen
monitors:       top htop btop gdu watch
REPL/intr:      gdb 'python3?' ipython node psql mysql sqlite3 claude
multi-word:     'git[[:space:]]+lz'
```

### FR-5. `bell_skip` 런타임 API

```
bell_skip                       # list current patterns
bell_skip += <pat>...           # add (idempotent), echoes only added: "+ pat"
bell_skip -= <pat>...           # remove, echoes only removed: "- pat"
bell_skip add <pat>...          # alias of +=
bell_skip remove <pat>... | rm  # alias of -=
bell_skip test <command...>     # dry-run: "SKIP: ..." or "NOTIFY: ..."
bell_skip help | -h | --help
```

- 패턴은 ERE⁷ 정규식. 명령 줄 시작에 anchor (`^`).
- 멀티워드는 `[[:space:]]+` 사용 (e.g. `git[[:space:]]+lz`).
- `sudo` prefix 자동 허용 — `vim` 패턴은 `sudo vim`도 잡지만 `vimdiff`는 안 잡음.
- mutation 후 echo는 *실제 변경된 항목*만 (전체 list 재출력 X — 노이즈 방지).

> ⁷ ERE (Extended Regular Expression): bash `=~` 연산자가 사용하는 POSIX 정규식. `?`, `+`, `|`, `(...)` 등을 backslash 없이 사용.

### FR-6. 비-interactive shell에서 비활성
모든 entry point에 `[[ $- == *i* ]]` 가드. 다음 컨텍스트에서 hook과 `bell` 모두 inert:
- LLM agent의 `bash_tool` (Claude Code, Cursor 등)
- `./script.sh` 내부 sub-command (script 부모 shell은 non-interactive)
- `bash -c '...'`
- `sshd`의 원격 명령 exec

### FR-7. Exit code 보존
`PROMPT_COMMAND` 체인 내부에서 `$?`를 즉시 capture, 모든 hook 처리 후 `(exit "$captured")` idiom으로 PS1이 볼 `$?`를 원래 값으로 복원.

### FR-8. PROMPT_COMMAND 공존
source 시점의 기존 `$PROMPT_COMMAND`를 `__bell_bash_prev_pc`로 보존, hook 처리 후 `eval`로 호출. starship, direnv, history sync 등과 충돌 없이 공존.

### FR-9. Idempotent source
`PROMPT_COMMAND`에 hook이 이미 체인되어 있는지 (`*"__bell_bash_post"*` 패턴) 검사 후 추가. 같은 파일을 여러 번 source해도 중복 체인 안 됨.

### FR-10. Skip list override
사용자가 source **이전에** `BELL_BASH_SKIP_LIST` 배열을 정의하면 default 무시 (`declare -p ... >/dev/null 2>&1` 검사).

### FR-11. Installer — `.bashrc` 통합
- `~/.bashrc`에 마커 블록 `# >>> bell-bash >>>` / `# <<< bell-bash <<<` 사이에 다음을 삽입:
  ```bash
  export BELL_BASH_THRESHOLD=<chosen>
  export BELL_BASH_BACKENDS='<chosen>'
  source <install-dir>/bell-bash.sh
  ```
- 재실행 시 기존 마커 블록을 in-place 교체. **trailing blank line 누적도 방지** (블록 제거 후 후행 blank line들도 함께 제거).
- 매 실행 전 timestamped backup: `~/.bashrc.bell-bash.bak.YYYYMMDD-HHMMSS`.

### FR-12. Installer — `.tmux.conf` 통합
같은 마커 블록 안에 다음을 삽입:
```tmux
setw -g monitor-bell on
set  -g visual-bell on
set  -g bell-action <chosen>
setw -g window-status-bell-style 'fg=black,bg=yellow,bold'
```

`<chosen>`은 다음에서 선택: `none` / `current` / `other` (기본) / `any`. `.tmux.conf`가 존재할 때만 사용자에게 묻고, 없을 때는 묻지 않고 생성 + 기본 `other`.

### FR-13. Installer — tmux 충돌 검사
설치 전에 마커 블록 **바깥**에서 다음 패턴을 탐지:
- `monitor-bell\s+off`
- `visual-bell\s+off`

탐지 시:
- 대화형: 코멘트 처리할지 묻기. **기본 no** (사용자 설정 보존이 안전한 default).
- yes 선택 → `# [bell-bash] commented out:  <원본>` 형태로 prefix.
- no 선택 → 사용자 라인 그대로 두고 우리 블록은 끝에 append. tmux는 last-write-wins이므로 우리 설정이 override됨 (UX 메시지에서 이 점 명확히 안내).

### FR-14. Installer CLI 인터페이스
모든 대화형 prompt는 flag로 우회 가능:

```
install.sh [OPTIONS]
  --uninstall              마커 블록만 제거, 백업 생성, install dir은 보존
  --yes, --all             모든 prompt에서 declared default 사용
                           (install confirmations는 yes, conflict override는 no
                            — 사용자 설정을 silent clobber 안 함)
  --no-bashrc              .bashrc 수정 skip
  --no-tmux                .tmux.conf 수정 skip
  --threshold=N            자동 trigger 임계값 (기본 5)
  --bell-action=VAL        none|current|other|any (기본 other)
  --backends=LIST          콤마 분리 (기본 bel)
  -h, --help
```

비대화형 행동 규칙:
- `! [[ -t 0 ]]` (stdin이 tty 아님) 또는 `--all` 시 모든 prompt는 declared default로.
- `--yes`/`--all`이 "yes to everything"이 아니라 "use declared defaults"인 이유: conflict-override prompt의 default가 no이므로, 자동화 모드에서도 사용자 설정을 함부로 덮어쓰지 않음.

### FR-15. Installer — backend 선택 대화형 흐름
1. `notify-send` PATH에 있으면 → "Enable desktop toasts via notify-send? [Y/n]" (기본 yes)
2. `noti` PATH에 있으면 → "Enable webhook alerts via 'noti send'? [y/N]" (기본 no)
3. `NOTI_WEBHOOK` 없는데 webhook 선택 시 → 경고 메시지 (silent fail됨을 안내).

### FR-16. Uninstall
`--uninstall`은 다음만 수행:
- `.bashrc`, `.tmux.conf`의 마커 블록 제거 (backup 후)
- 라이브러리 디렉토리(`~/.bell-bash/`)는 보존, 안내 메시지 출력

---

## 7. 비기능 요구사항 (Non-Functional Requirements)

| ID | 요구사항 |
|---|---|
| NFR-1 | 프롬프트 추가 지연 < 5 ms. 모든 backend 호출은 background detached subshell. |
| NFR-2 | Bash ≥ 5.0 필요 (`$EPOCHREALTIME` 의존). 미달 시 source가 silent return. |
| NFR-3 | `install.sh`는 `set -euo pipefail`. 모든 파일 쓰기 전 backup. |
| NFR-4 | 외부 의존성: `awk` (POSIX). `notify-send`, `noti`, `tmux`는 optional. |
| NFR-5 | webhook URL을 로그/stdout에 평문 노출 금지 (`noti` 본체의 마스킹 정책 상속). |
| NFR-6 | webhook 호출 실패/지연이 프롬프트를 막지 않는다 (`& disown`). |
| NFR-7 | ANSI 컬러 출력은 `install.sh`만 사용. 라이브러리는 plain text. |

---

## 8. 아키텍처

### 8.1 컴포넌트

```
┌────────────────────────────────────────────────────────────────┐
│  ~/.bashrc                                                     │
│    # >>> bell-bash >>>                                        │
│    export BELL_BASH_THRESHOLD=5                                │
│    export BELL_BASH_BACKENDS='bel'                            │
│    source ~/.bell-bash/bell-bash.sh                          │
│    # <<< bell-bash <<<                                        │
│           │                                                    │
│           ↓                                                    │
│  ~/.bell-bash/bell-bash.sh                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Triggers                                                 │  │
│  │   ├── auto-hook  (PS0 + PROMPT_COMMAND, threshold-based) │  │
│  │   └── bell()    (explicit, wrapper/postfix)             │  │
│  │              ↓                                           │  │
│  │       __bell_bash_dispatch(exit_code, title, body)           │  │
│  │              ↓                                           │  │
│  │     for each backend in $BELL_BASH_BACKENDS:            │  │
│  │   ┌──────────┬──────────────┬─────────────────────────┐  │  │
│  │   │   bel    │ notify-send  │  webhook (noti send)    │  │  │
│  │   └────┬─────┴──────┬───────┴────────────┬────────────┘  │  │
│  │        ↓            ↓                    ↓               │  │
│  │   terminal       desktop            Slack/Discord        │  │
│  │   or tmux        toast              channel              │  │
│  │   monitor-bell                                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  ~/.tmux.conf                                                  │
│    # >>> bell-bash >>>                                        │
│    setw -g monitor-bell on                                     │
│    set  -g visual-bell on                                      │
│    set  -g bell-action other                                   │
│    setw -g window-status-bell-style 'fg=black,bg=yellow,bold'  │
│    # <<< bell-bash <<<                                        │
└────────────────────────────────────────────────────────────────┘
```

### 8.2 자동 trigger 흐름

```
[user submits command]
        │
        ▼
   PS0 → __bell_bash_pre()
        - __bell_bash_start = $EPOCHREALTIME
        - __bell_bash_cmd   = $(history 1 | sed 's/^[0-9 ]*//')
        │
        ▼
   [command runs]
        │
        ▼
   PROMPT_COMMAND chain:
        - exit_code = $?              # capture immediately
        - __bell_bash_post "$exit_code"
            - elapsed = (now - start) via awk
            - if elapsed >= threshold:
                - if cmd matches BELL_BASH_SKIP_REGEX: return
                - title/body 생성, __bell_bash_dispatch 호출
        - eval "$__bell_bash_prev_pc"  # 기존 prompt hook 호출
        - (exit "$exit_code")          # PS1이 볼 $? 복원
        │
        ▼
   PS1 prints
```

### 8.3 Skip-list 파이프라인

```
BELL_BASH_SKIP_LIST     (bash array, source of truth)
        │
        ▼
__bell_bash_rebuild_skip_regex
   - IFS='|' joins
   - wraps: ^(sudo[[:space:]]+)?(joined)([[:space:]]|$)
        │
        ▼
BELL_BASH_SKIP_REGEX    (ERE string, consumed by hot path)
```

`bell_skip +=` / `-=`는 배열 mutate → rebuild 호출. Hot path(`__bell_bash_post`)는 미리 빌드된 regex만 사용 → 매 명령마다 join 비용 없음.

### 8.4 에이전트/스크립트 자동 제외 메커니즘

`PS0` / `PROMPT_COMMAND`는 **interactive bash에서만** 평가된다. 이 단일 사실이 다음을 모두 커버:

- LLM agent의 `bash_tool` → `bash -c` 또는 non-interactive spawn
- 사용자가 친 `./script.sh` → script 내부는 새 non-interactive shell
- `ssh host 'cmd'` → 원격에서 non-interactive exec

별도 감지 로직 불필요. `bell` 함수도 `[[ $- == *i* ]]` 가드로 같은 컨텍스트에서 silent.

⚠️ 단, 사용자가 친 `./script.sh` 자체는 *부모 interactive shell*이 측정 → script 전체 시간이 한 줄의 명령으로 잡힘. 이는 의도된 동작.

---

## 9. 설치 흐름 (install.sh)

```
parse_args
    ↓
sanity checks (라이브러리/template 파일 존재 확인)
    ↓
if action == uninstall: do_uninstall; exit
    ↓
step_copy_lib            라이브러리 → $INSTALL_DIR (기본 ~/.bell-bash)
    ↓
step_choose_backends     notify-send/noti 존재 여부 검사 후 사용자 선택
    ↓
step_install_bashrc
    ├ "Install hook into ~/.bashrc? [Y/n]" (기본 yes)
    ├ backup
    ├ remove existing block (trailing blanks 포함)
    └ append new block (env vars + source line)
    ↓
step_install_tmux
    ├ bell-action 선택 (.tmux.conf 있을 때만 묻기, 기본 other)
    ├ "Update ~/.tmux.conf? [Y/n]"
    ├ conflict detection (monitor-bell off, visual-bell off)
    │   └ "Comment out for clarity? [y/N]" (기본 no; tmux는 어차피 override됨을 안내)
    ├ backup
    ├ comment out conflicts (yes 선택 시)
    ├ remove existing block
    ├ append new block (substituted bell-action)
    └ tmux 실행 중이면 `tmux source-file ~/.tmux.conf` 안내
    ↓
step_summary             빠른 동작 확인 명령 제시
```

---

## 10. 산출물 파일 구조

```
bell-bash/
├── install.sh                  # 실행권한, fzf 스타일 installer
├── bell-bash.sh               # 메인 라이브러리 (~/.bashrc에서 source)
├── bell-bash.tmux.conf        # tmux 설정 template (@BELL_ACTION@ placeholder)
├── README.md                   # 프로젝트 소개, env vars, 사용법 reference
├── GUIDE.md                    # 사용자 가이드 (시나리오, 트러블슈팅, FAQ)
├── PRD.md                      # 본 문서
└── LICENSE                     # TBD
```

설치 후 사용자 시스템:
```
$HOME/.bell-bash/bell-bash.sh         # 라이브러리 사본 (installer가 복사)
$HOME/.bashrc                            # 마커 블록 삽입됨
$HOME/.tmux.conf                         # 마커 블록 삽입됨 (선택)
$HOME/.bashrc.bell-bash.bak.<stamp>     # 매 설치 시 백업
$HOME/.tmux.conf.bell-bash.bak.<stamp>  # 매 설치 시 백업
```

---

## 11. 핵심 구현 디테일

### 11.1 BEL은 stderr로
```bash
printf '\a' >&2
```
**이유**: `$(some_cmd)` 같은 command substitution에서 stdout만 캡처된다. stdout으로 BEL을 보내면 사용자가 `result=$(bell ...)` 같은 패턴 쓸 때 BEL이 변수에 들어가 출력 안 됨. stderr는 캡처 안 되므로 안전.

### 11.2 `history 1`로 명령 텍스트 추출
```bash
__bell_bash_cmd=$(HISTTIMEFORMAT='' history 1 2>/dev/null \
    | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+//')
```
- `HISTTIMEFORMAT=''`로 잠시 timestamp 제거 (만약 사용자가 설정해뒀다면).
- `sed`로 history 번호 prefix 제거.
- **한계**: `HISTCONTROL=ignorespace` + 선행 공백 명령 시 history에 안 들어가므로 직전 entry가 반환됨. 시간 측정은 정확하나 메시지의 명령어 텍스트는 부정확. → 문서화로 처리.

### 11.3 fire-and-forget background
```bash
( noti send "$msg" >/dev/null 2>&1 & disown ) 2>/dev/null
```
- subshell 안에서 fork → 즉시 parent subshell 종료 → noti는 init에 reparent.
- prompt latency 0.
- 실패해도 사용자 셸에 영향 없음.

### 11.4 PROMPT_COMMAND 체인 (exit code 보존 포함)
```bash
if [[ "$PROMPT_COMMAND" != *"__bell_bash_post"* ]]; then
    __bell_bash_prev_pc=$PROMPT_COMMAND
    PROMPT_COMMAND='__bell_bash_exit=$?
__bell_bash_post "$__bell_bash_exit"
[[ -n "$__bell_bash_prev_pc" ]] && eval "$__bell_bash_prev_pc"
(exit "$__bell_bash_exit")'
fi
```
**핵심 포인트**:
- `__bell_bash_exit=$?`를 **PROMPT_COMMAND 첫 줄로**: 이후 어떤 명령이 실행되든 사용자 명령의 원래 exit code를 잃지 않음.
- `(exit "$__bell_bash_exit")`: subshell이 즉시 종료하며 그 exit를 부모(=PROMPT_COMMAND 평가 컨텍스트)의 `$?`로 남김. PS1이 이 `$?`를 본다.
- idempotency guard: hook이 이미 들어있으면 재추가 안 함.

### 11.5 awk float 비교
```bash
elapsed=$(awk -v s="$start" -v e="$EPOCHREALTIME" 'BEGIN{ printf "%.2f", e - s }')
if awk -v e="$elapsed" -v t="$BELL_BASH_THRESHOLD" 'BEGIN{ exit !(e + 0 >= t + 0) }'; then
    ...
fi
```
bash는 정수만 비교 가능. float은 awk로 위임. `exit !(condition)` 패턴으로 boolean을 process exit code로 전달.

### 11.6 Skip regex 빌드
```bash
__bell_bash_rebuild_skip_regex() {
    if (( ${#BELL_BASH_SKIP_LIST[@]} == 0 )); then
        BELL_BASH_SKIP_REGEX=''
    else
        BELL_BASH_SKIP_REGEX="^(sudo[[:space:]]+)?($(IFS='|'; echo "${BELL_BASH_SKIP_LIST[*]}"))([[:space:]]|$)"
    fi
}
```
- `(IFS='|'; echo "${arr[*]}")`: subshell 안에서 IFS 변경 → 배열 join → 부모 IFS 영향 없음.
- 트레일링 `([[:space:]]|$)`: 단어 경계 효과. `vim`이 `vimdiff` 매치 안 함.
- 옵셔널 `sudo` prefix.

### 11.7 마커 기반 in-place 교체 (idempotency)
installer의 `remove_block` 함수가 awk로 처리:
```awk
$0 == BEGIN_MARKER { skip = 1 }
!skip {
    if ($0 ~ /^[[:space:]]*$/) {
        buf = buf $0 "\n"        # blank line buffer
    } else {
        printf "%s", buf          # flush buffered blanks
        buf = ""
        print
    }
}
$0 == END_MARKER { skip = 0; next }
END { }  # buf의 trailing blanks는 의도적으로 폐기
```

**왜 이렇게?** 단순 sed로 `BEGIN..END`를 지우면 블록 뒤의 빈 줄이 남고, append 시 또 빈 줄이 추가되어 재실행마다 빈 줄이 누적됨. blank line을 버퍼링하고 *비-blank 라인이 따라올 때만* flush하면, EOF까지 비-blank이 안 오는 trailing blanks는 자연스럽게 폐기됨.

### 11.8 conflict 탐지 (`has_user_setting`)
사용자가 마커 블록 *바깥*에 명시적으로 적은 설정만 탐지:
```awk
$0 == BEGIN_MARKER { inside = 1; next }
$0 == END_MARKER   { inside = 0; next }
!inside && $0 ~ pattern { found = 1 }
END { exit !found }
```
이전 설치로 인해 우리 블록 *내부*에 `monitor-bell on`이 들어있어도 탐지 안 함 (false positive 방지).

### 11.9 `ask_yn` 비대화형 처리
```bash
ask_yn() {
    local prompt=$1 default=${2:-no}
    if (( ASSUME_YES )) || ! [[ -t 0 ]]; then
        [[ "$default" == yes ]]  # exit code로 return
        return
    fi
    # tty가 있을 때만 대화형 read
    ...
}
```
**핵심**: `--all`이 "force yes"가 아니라 "use declared default". 호출 측에서 default를 yes/no로 의도적으로 지정 → 안전한 자동화.

---

## 12. 알림 메시지 포맷

### 자동 trigger
```
title:  ✅ done (312.47s)            (성공)
        ❌ failed exit 101 (87.13s)  (실패)
body:   <user command text>
        host: <hostname -s>  cwd: <PWD>
```

### 명시 trigger (`bell`)
```
title:  ✅ done                       (성공)
        ❌ failed (exit 7)            (실패)
body:   <args joined> 또는 "previous command"
        host: <hostname -s>  cwd: <PWD>
```

### Backend별 변환
- **bel**: 텍스트 표시 안 함, BEL만 출력
- **notify-send**: `notify-send -u <urgency> -t $BELL_BASH_TIMEOUT_MS "<title>" "<body>"`. urgency는 exit 0이면 `normal`, 아니면 `critical`.
- **webhook**: `noti send "<title> — <body>"` — 한 줄로 join.

---

## 13. 환경변수 reference

| 변수 | 기본값 | 의미 |
|---|---|---|
| `BELL_BASH_THRESHOLD` | `5` | 자동 trigger 임계(초). float 허용. |
| `BELL_BASH_BACKENDS` | `bel` | 콤마 분리. `bel,notify-send,webhook` 조합. |
| `BELL_BASH_TIMEOUT_MS` | `4000` | notify-send 토스트 표시 시간 (ms). |
| `BELL_BASH_SKIP_LIST` | (배열, default 포함) | source 이전에 정의하면 default 대체. |
| `BELL_BASH_SKIP_REGEX` | 자동 빌드 | 직접 수정 금지 (rebuild에서 덮어씀). |
| `NOTI_WEBHOOK` | — | webhook backend 사용 시 필요. `noti` 본체에서 사용. |
| `BELL_BASH_HOME` | `$HOME/.bell-bash` | installer가 라이브러리를 둘 디렉토리. |

---

## 14. 테스트 매트릭스

| ID | 시나리오 | 기대 |
|---|---|---|
| T1 | `sleep 6` (기본 임계 5) | 알림 발사 (enabled backends 모두) |
| T2 | `sleep 3` | 알림 없음 |
| T3 | `vim` 10초 후 종료 | 알림 없음 (skip-list) |
| T4 | `bash -c 'sleep 10'` | 알림 발사 (interactive 부모가 측정) |
| T5 | `./script.sh`에서 `sleep 10` | 알림 발사 (script 전체 시간) |
| T6 | `bell echo hi` | 알림 발사, exit 0 반환 |
| T7 | `bell bash -c 'exit 7'` | 알림 발사 (failure), **exit 7 반환** |
| T8 | `false; bell` (postfix) | 알림 발사, exit 1 반환 |
| T9 | `bell_skip += tig` 후 `tig status` 6초 실행 | 알림 없음 |
| T10 | `bell_skip += tig` 후 `tigress` 6초 실행 | 알림 발사 (anchored regex) |
| T11 | installer 재실행 (--all) | `.bashrc`/`.tmux.conf` 라인 수 불변 |
| T12 | installer + 기존 `monitor-bell off` + 사용자 no | 사용자 라인 보존, 우리 block append |
| T13 | `--uninstall` | block만 제거, 백업 생성, 라이브러리 보존 |
| T14 | bash 4.x 환경 | source 시 silent return, hook 미설치 |
| T15 | non-interactive shell (`bash -c 'source ... && echo x'`) | hook 미설치, `bell` inert |
| T16 | `bell_skip += foo \| grep bar` (파이프 호출) | 배열 변경 무효 (subshell scope) — 의도된 동작, 문서화 |
| T17 | `BELL_BASH_BACKENDS=webhook` + `NOTI_WEBHOOK` 미설정 | silent no-op, 에러 없음 |
| T18 | starship + bell-bash 동시 설치 | 정상 공존, `$?` 정확 |

---

## 15. 리스크

| ID | 리스크 | 영향 | 완화 |
|---|---|---|---|
| R1 | tmux 실행 중일 때 `source-file`을 안 하면 새 설정이 안 보임 | 낮음 | installer가 안내 |
| R2 | `HISTCONTROL=ignorespace` + 선행 공백 명령 → 메시지 텍스트 부정확 | 낮음 | 문서화 |
| R3 | bash 5.1+ array 형식 `PROMPT_COMMAND` 환경 | 중간 | v0.1은 string 형식만; future work |
| R4 | `notify-send`가 GUI 세션 외부에서 실패 | 낮음 | silent no-op (backend가 보호) |
| R5 | webhook backend가 네트워크 끊김에서 stall | 낮음 | detached subshell + `noti` 자체 timeout |
| R6 | `bell` 함수와 `bel` backend 이름이 한 글자 차이로 헷갈릴 수 있음 | 낮음 | `bell()`은 사용자 함수, `bel`은 `BELL_BASH_BACKENDS=bel,...`의 내부 식별자. README/GUIDE에서 분리해서 설명. |
| R7 | `NOTI_WEBHOOK`이 `.bashrc`에 평문 저장될 수 있음 | 중간 | 가이드에 dotfiles repo 커밋 금지 명시 |

---

## 16. Future Work

| ID | 항목 |
|---|---|
| FW1 | zsh port (`preexec` / `precmd`) |
| FW2 | 명령별 임계값 (`make`는 30s, 그 외 5s) |
| FW3 | webhook embed 카드 (Slack attachments, Discord embeds — 색상/필드) |
| FW4 | 영구 skip-list 파일 (`~/.config/bell-bash/skip.list`) |
| FW5 | direnv 통한 프로젝트별 skip override |
| FW6 | 백그라운드 job (`cmd &`) 완료 알림 |
| FW7 | `--force-tmux-override` flag (비대화형 conflict 강제 정리) |
| FW8 | Tab completion for `bell_skip` |
| FW9 | macOS 지원 (`terminal-notifier` backend) |
| FW10 | 알림 rate limit (5초 내 중복 발사 억제) |
| FW11 | bash 5.1+ array `PROMPT_COMMAND` 네이티브 지원 |
| FW12 | `bell` summary 옵션 (`bell --time-only`, `bell --quiet` 등) |

---

## 17. 채택 기준 (Acceptance Criteria)

- [ ] 14. 테스트 매트릭스 T1–T18 모두 통과
- [ ] `install.sh` 재실행 시 byte-idempotent (라인 수, 백업 외 변경 없음)
- [ ] `--uninstall` 후 `.bashrc` / `.tmux.conf`에 bell-bash 잔존물 0
- [ ] BEL 단독 backend(의존성 0) 환경에서 tmux + 터미널 모두 동작
- [ ] `README.md`, `GUIDE.md`, `PRD.md` 산출
- [ ] `install.sh`, `bell-bash.sh` 모두 `bash -n` 통과, `shellcheck -S warning` warning 없음 (info는 허용)

---

## 18. 구현 순서 권장

1. **bell-bash.sh 골격**: 가드 + config + `__bell_bash_dispatch` + `bel` backend만. `bell` 함수 wrapper/postfix 두 모드.
2. **자동 hook**: `PS0` + `PROMPT_COMMAND` 체인, exit code 보존, 시간 측정, idempotency guard.
3. **Skip list**: 배열 + `__bell_bash_rebuild_skip_regex` + `bell_skip` 함수 (list/add/remove/test/help).
4. **추가 backends**: `notify-send`, `webhook`. 각각 prerequisite 검사.
5. **install.sh — 기본**: 인자 파싱, `--help`, `step_copy_lib`, `step_install_bashrc`.
6. **install.sh — tmux**: template 처리, bell-action 선택, conflict 탐지/override.
7. **install.sh — uninstall** + 마커 기반 in-place 교체 + trailing blank 처리.
8. **테스트 매트릭스 실행**, 발견한 issue 수정.
9. **README + GUIDE 작성**.

각 단계에서 `bash -n` + 임시 `$HOME`을 만들어 실제 install/source/uninstall을 돌려보면서 진행.

---

## 19. 참고

- noti-bash repo: <https://github.com/tot0rokr/noti-bash>
- Bash Reference Manual §6.9 (Controlling the Prompt), §4.3 (`EPOCHREALTIME`, `PROMPT_COMMAND`, `PS0`)
- tmux manpage: bell-action, monitor-bell, visual-bell sections
