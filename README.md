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
git clone https://github.com/tot0rokr/bell-bash.git ~/.bell-bash
~/.bell-bash/install       # 대화형 (notify-send / webhook / Claude skill 사용 여부 물음)
~/.bell-bash/install --all # 비대화형, 안전한 default 사용
~/.bell-bash/install --uninstall   # 마커 블록 + skill symlink 제거 (repo는 보존)
~/.bell-bash/install --help        # 모든 flag 목록
```

**clone-in-place 모델** — repo 위치가 곧 install 위치. installer는 파일을 복사하지 않고, `~/.bashrc` 와 `~/.tmux.conf` 에 마커 블록 `# >>> bell-bash >>>` ~ `# <<< bell-bash <<<` 만 in-place 작성한다.

- 업데이트: `cd ~/.bell-bash && git pull` — install 재실행 불필요. `bell` / `bell-send` 가 바로 갱신된 코드를 가리키니까 새 터미널부터 적용됨.
- `./install` 재실행은 idempotent — 마커 블록이 desired 와 동일하면 백업도 안 만들고 그냥 `already up to date` log. threshold/backends 같은 설정을 바꿀 때만 다시 돌리면 됨.
- 다른 경로 (`~/projects/bell-bash` 등) 에 클론해도 됨. installer 는 자기 위치를 기준으로 path를 등록 — README 의 `~/.bell-bash` 는 권장 위치일 뿐.
- Claude Code skill은 `~/.claude/skills/bell → <repo>/skills/bell` symlink (`--no-skill` 로 skip 가능).
- 백업은 진짜 갱신이 일어날 때만 timestamped 로 생성됨 (`~/.bashrc.bell-bash.bak.YYYYMMDD-HHMMSS`).

설치 후 새 터미널을 열거나 `source ~/.bashrc` 후 사용.

---

## 동작 원리 (한 줄 요약)

| Trigger | When | 알림 메시지 |
|---|---|---|
| **자동** | 사용자가 친 명령이 `BELL_BASH_THRESHOLD`초 이상 걸림 (실패도 동일) | `✅ done (312.47s)` / `❌ failed exit 7 (87.13s)` + 명령 라인 |
| **명시 wrapper** | `bell <cmd>` 로 wrapping | exit code 그대로 반환. duration 측정해서 본문에 포함 |
| **명시 postfix** | `cmd1; bell` (직전 `$?` 캡처) | bash-preexec 의 start time 으로 duration 채움. 명령 본문은 `history 1` 라인 (`cmd1; bell` 형태 그대로) |

자동 trigger는 [`bell_skip`](#skip-list-제어) 패턴에 매치되는 인터랙티브 프로그램 (`vim`, `ssh`, `tmux`, `top` 등)은 자동 제외.
명시 `bell` 호출은 skip-list와 무관하게 항상 발사.

LLM 에이전트의 `bash_tool`, `bash -c`, `./script.sh` 내부, `ssh host cmd` 같은 비-interactive 컨텍스트에서는 hook과 `bell` 함수 둘 다 inert. 별도 감지 로직 없이 `[[ $- == *i* ]]` 가드 하나로 커버된다.

---

## 백엔드

`BELL_BASH_BACKENDS` (콤마 분리, default `bel,notify-send`) 에 enable된 백엔드만 호출된다. prerequisite 미충족 백엔드는 silent no-op이라 다른 백엔드는 정상 동작한다. 한 번만 다른 조합을 쓰고 싶으면 `bell --backends=webhook make` 식으로 per-call override 가능.

`bell-send` standalone CLI는 동일한 백엔드 조합을 비-interactive 컨텍스트(스크립트, cron, Claude Code 같은 agent의 bash_tool)에서 발사한다 — interactive 가드와 무관하게 동작. Claude Code skill (`skills/bell/SKILL.md`)이 이걸 이용해서 응답 끝에 desktop toast, 긴 작업 끝에 webhook까지 자동으로 쏘게 한다.

| 백엔드 | 의존성 | 효과 |
|---|---|---|
| `bel` | 없음 | ASCII BEL (0x07) → stderr. tmux 의 `monitor-bell` 이 받아 window flag 강조. 터미널 에뮬레이터가 받으면 종소리 (or visual bell, 터미널 설정에 의존). |
| `notify-send` | `libnotify-bin` + GUI 세션 | 데스크톱 토스트. 실패 시 `urgency=critical`. |
| `webhook` | `noti` CLI + `NOTI_WEBHOOK` env | `noti embed` 로 Slack/Discord 카드 발사. 색상 사이드바 (성공=초록, 실패=빨강) + 명령 코드블록 desc + Duration/Host/CWD 필드. |

> **명명 주의** — 함수 `bell()` (사용자가 직접 호출) 과 백엔드 식별자 `bel` (env var 값) 은 한 글자 차이지만 다르다. `bell make` 는 함수 호출, `BELL_BASH_BACKENDS=bel,notify-send` 는 백엔드 선택.

---

## 환경 변수

| 변수 | 기본값 | 의미 |
|---|---|---|
| `BELL_BASH_THRESHOLD` | `5` | 자동 trigger 임계값(초). float 허용. |
| `BELL_BASH_BACKENDS` | `bel` (lib) / installer 가 환경에 따라 `bel,notify-send[,webhook]` 으로 작성 | 콤마 분리. `bel,notify-send,webhook` 조합 가능. |
| `BELL_BASH_TIMEOUT_MS` | `4000` | notify-send 토스트 표시 시간 (ms). |
| `BELL_BASH_SKIP_LIST` | (배열, default 포함) | source **이전**에 정의하면 default 대체. |
| `BELL_BASH_HOME` | `$REPO_DIR` (installer 가 자동 감지) | installer 가 등록할 install 위치. clone-in-place 모델이므로 보통 repo 자체. |
| `NOTI_WEBHOOK` | — | `webhook` 백엔드 사용 시 필요. [`noti`](https://github.com/tot0rokr/noti-bash) 본체에서 사용. |

`BELL_BASH_BASHRC` / `BELL_BASH_TMUXCONF` / `BELL_BASH_SKILL_LINK` 는 테스트용으로 installer가 대상 경로를 override할 수 있다.

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
- `git` → `git status`, `git log`, `git lg`, `git df` 등 전부 매치, `gitlab` / `gitk` 는 미매치 (word boundary 덕분)
- `python3?` → `python` 또는 `python3` 매치
- multi-word 패턴이 필요하면 `[[:space:]]+` 로 (예: `'svn[[:space:]]+update'`)

Default 목록(28개)은 `bell_skip` 으로 확인 — editors / pagers / mux / monitors / REPL + `git` 전체. 영구히 다른 default를 쓰려면 `BELL_BASH_SKIP_LIST=( ... )` 를 source **이전에** 정의.

---

## tmux 통합

설치 시 `~/.tmux.conf` 에 다음이 들어간다:

```tmux
setw -g monitor-bell on
set  -g visual-bell off            # 텍스트 팝업 끔 (toast/webhook 과 중복)
set  -g bell-action other          # none|current|other|any
setw -g window-status-bell-style 'fg=#000000,bg=yellow,bold'
```

다른 창에서 빌드 끝났을 때 status line 의 해당 window 가 노란 배경으로 강조된다. tmux 의 `visual-bell` 텍스트 팝업은 의도적으로 off — desktop toast / webhook 알림과 겹쳐 시끄러워서. tmux 가 실행 중이면 설치 후 `tmux source-file ~/.tmux.conf` 가 필요.

기존 `.tmux.conf` 에 `monitor-bell off` 같은 충돌 라인이 있으면 installer 가 발견해 알리고 코멘트 처리할지 묻는다 (기본 no — 사용자 설정 보존). 우리 블록은 last-write-wins 이므로 코멘트 처리 안 해도 동작은 한다.

---

## 라이선스

BSD-3-Clause. [`LICENSE`](./LICENSE).
