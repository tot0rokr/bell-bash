# bell-bash

긴 명령이 끝났을 때 즉시 인지할 수 있게 해주는 bash 훅 + `bell` 함수.
의존성 0의 기본 모드로 동작하고, 환경이 갖춰지면 desktop toast/webhook도 같이 보낸다.

```
$ make -j8                    # 6분 걸려서 끝나면 자동으로 알림
$ bell ./run_tests.sh         # 결과 알림 (성공/실패 + exit code)
$ make && ./deploy.sh; bell   # 직전 명령의 $? 를 캡처해 알림
```

상세 스펙은 [`PRD.md`](./PRD.md), 사용 시나리오/트러블슈팅은 [`GUIDE.md`](./GUIDE.md).

---

## 설치

```bash
git clone https://github.com/<your-fork>/bell-bash.git
cd bell-bash
./install                  # 대화형 (notify-send / webhook 백엔드 사용 여부 물음)
./install --all            # 비대화형, 안전한 default 사용
./install --uninstall      # 마커 블록만 제거 (라이브러리 디렉토리는 보존)
./install --help           # 모든 flag 목록
```

- `~/.bashrc` 와 `~/.tmux.conf` (있으면)에 마커 블록 `# >>> bell-bash >>>` ~ `# <<< bell-bash <<<`이 in-place로 들어간다.
- 매 설치 전 timestamped 백업 (`~/.bashrc.bell-bash.bak.YYYYMMDD-HHMMSS`).
- 라이브러리는 `~/.bell-bash/bell`에 복사.
- 재실행해도 라인이 누적되지 않음 (idempotent).

설치 후 새 터미널을 열거나 `source ~/.bashrc` 후 사용.

---

## 동작 원리 (한 줄 요약)

| Trigger | When | 알림 메시지 |
|---|---|---|
| **자동** | 사용자가 친 명령이 `BELL_BASH_THRESHOLD`초 이상 걸림 | `✅ done (312.47s)` / `❌ failed exit 7 (87.13s)` |
| **명시 wrapper** | `bell <cmd>` 로 wrapping | `✅ done` / `❌ failed (exit 7)`, exit code는 그대로 반환 |
| **명시 postfix** | `cmd1; bell` (직전 `$?` 캡처) | 위와 동일, body는 `previous command` |

자동 trigger는 [`bell_skip`](#skip-list-제어) 패턴에 매치되는 인터랙티브 프로그램 (`vim`, `ssh`, `tmux`, `top` 등)은 자동 제외.
명시 `bell` 호출은 skip-list와 무관하게 항상 발사.

LLM 에이전트의 `bash_tool`, `bash -c`, `./script.sh` 내부, `ssh host cmd` 같은 비-interactive 컨텍스트에서는 hook과 `bell` 함수 둘 다 inert. 별도 감지 로직 없이 `[[ $- == *i* ]]` 가드 하나로 커버된다.

---

## 백엔드

`BELL_BASH_BACKENDS` (콤마 분리, default `bel`) 에 enable된 백엔드만 호출된다. prerequisite 미충족 백엔드는 silent no-op이라 다른 백엔드는 정상 동작한다.

| 백엔드 | 의존성 | 효과 |
|---|---|---|
| `bel` | 없음 | ASCII BEL (0x07) → stderr. tmux의 `monitor-bell`이 받아 visual bell + window flag로 변환. 터미널 에뮬레이터가 받으면 종소리. |
| `notify-send` | `libnotify-bin` + GUI 세션 | 데스크톱 토스트. 실패 시 `urgency=critical`. |
| `webhook` | `noti` CLI + `NOTI_WEBHOOK` env | `noti send` 로 Slack/Discord webhook 전송. |

> **명명 주의** — 함수 `bell()` (사용자가 직접 호출) 과 백엔드 식별자 `bel` (env var 값) 은 한 글자 차이지만 다르다. `bell make` 는 함수 호출, `BELL_BASH_BACKENDS=bel,notify-send` 는 백엔드 선택.

---

## 환경 변수

| 변수 | 기본값 | 의미 |
|---|---|---|
| `BELL_BASH_THRESHOLD` | `5` | 자동 trigger 임계값(초). float 허용. |
| `BELL_BASH_BACKENDS` | `bel` | 콤마 분리. `bel,notify-send,webhook` 조합. |
| `BELL_BASH_TIMEOUT_MS` | `4000` | notify-send 토스트 표시 시간 (ms). |
| `BELL_BASH_SKIP_LIST` | (배열, default 포함) | source **이전**에 정의하면 default 대체. |
| `BELL_BASH_HOME` | `$HOME/.bell-bash` | installer가 라이브러리를 둘 디렉토리. |
| `NOTI_WEBHOOK` | — | `webhook` 백엔드 사용 시 필요. [`noti`](https://github.com/tot0rokr/noti-bash) 본체에서 사용. |

`BELL_BASH_BASHRC` / `BELL_BASH_TMUXCONF` 는 테스트용으로 installer가 대상 conf 파일 경로를 override할 수 있다.

---

## skip-list 제어

```
$ bell_skip                   # 현재 패턴 목록
$ bell_skip += tig            # 추가 (idempotent, "+ tig" echo)
$ bell_skip -= tig            # 제거 ("- tig" echo)
$ bell_skip add make          # += 별칭
$ bell_skip remove make       # -= 별칭 (rm 도 동일)
$ bell_skip test sudo vim a   # SKIP: sudo vim a  / NOTIFY: ...
$ bell_skip help              # 전체 도움말
```

패턴은 POSIX ERE. 자동으로 줄 시작 anchor + 옵셔널 `sudo ` prefix + word-boundary tail 이 붙는다. 즉:

- `vim` → `sudo vim file` 매치, `vimdiff` 미매치
- `git[[:space:]]+lz` → `git lz` 매치 (multi-word)
- `python3?` → `python` 또는 `python3` 매치

Default 목록(28개)은 `bell_skip` 으로 확인. 영구히 다른 default를 쓰려면 `BELL_BASH_SKIP_LIST=( ... )` 를 source **이전에** 정의.

---

## tmux 통합

설치 시 `~/.tmux.conf` 에 다음이 들어간다:

```tmux
setw -g monitor-bell on
set  -g visual-bell on
set  -g bell-action other          # none|current|other|any
setw -g window-status-bell-style 'fg=black,bg=yellow,bold'
```

다른 창에서 빌드 끝났을 때 노란색 깜빡임 + status line 메시지로 표시된다. tmux가 실행 중이면 설치 후 `tmux source-file ~/.tmux.conf` 가 필요.

기존 `.tmux.conf` 에 `monitor-bell off` / `visual-bell off` 같은 충돌 라인이 있으면 installer가 발견해 알리고 코멘트 처리할지 묻는다 (기본 no — 사용자 설정 보존). 우리 블록은 last-write-wins이므로 코멘트 처리 안 해도 동작은 한다.

---

## 라이선스

BSD-3-Clause. [`LICENSE`](./LICENSE).
