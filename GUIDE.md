# bell-bash 사용 가이드

스펙: [`PRD.md`](./PRD.md). 빠른 reference: [`README.md`](./README.md).

---

## 시나리오

### 1. BSP 빌드 돌리고 자리 비울 때

```
$ make -j8
... 6분 후 ...
[BEL]                      # 터미널 종소리, tmux에서는 status line "Activity in ..."
```

`bel` 백엔드만으로도 tmux를 쓰고 있다면 다른 창에서 노란색 window flag로 즉시 보인다. GUI 데스크톱이면 notify-send 토스트도 함께 뜬다 (`./install --all` 으로 설치 시 자동 enable).

### 2. 결과까지 알림에 담고 싶을 때

```
$ bell ./run_tests.sh
... 30초 후 ...
# 알림: "❌ failed (exit 1) — ./run_tests.sh — host: dev cwd: /home/j/app"
$ echo $?
1
```

wrapper 모드는 `"$@"` 를 실행하고 그 exit code를 그대로 반환한다. 그래서 chain이 자연스럽다:

```
$ bell make && bell ./deploy.sh       # make 실패 시 알림+stop, 성공 시 deploy도 알림
$ bell make || echo "fix it"          # 알림 받고도 || 동작
```

### 3. 명령 줄에 미리 wrapping을 못 했을 때

```
$ ./very-long-thing
... 끝남, 그런데 자동 임계값 미달이라 알림이 안 옴 ...
$ bell                                # 직전 $? 캡처해서 알림
```

postfix 모드는 `bell` 만 단독 호출. 캡처는 `bell` 함수의 첫 줄에서 `$?` 를 잡아두기 때문에 `[[ ]]` 같은 후속 식이 끼어들어도 exit code가 보존된다.

### 4. 인터랙티브 프로그램에서 알림이 거슬릴 때

기본 skip-list가 이미 `vim`, `tmux`, `ssh`, `top`, `less`, `man` 등을 포함하니 알림이 안 온다. `vimdiff` 같이 prefix 만 같은 명령은 `vim` 패턴에 매치되지 *않는다* (단어 경계).

새 long-running 도구를 발견했을 때:

```
$ bell_skip += tig                    # "+ tig"
$ bell_skip test tig status           # "SKIP: tig status"
$ bell_skip test tigress              # "NOTIFY: tigress"  (anchored regex)
```

### 5. 일시적으로 default skip-list를 override하고 싶을 때

```bash
# .bashrc 에서 source 이전에:
BELL_BASH_SKIP_LIST=(vim ssh tmux)    # 최소화
source ~/.bell-bash/bell
```

이 경우 default 28개 패턴이 무시되고 위 3개만 적용.

### 6. webhook도 같이 보내고 싶을 때

`noti` CLI 설치 후:

```bash
export NOTI_WEBHOOK="https://hooks.slack.com/services/..."
# 또는 install 시 --backends=bel,notify-send,webhook
```

`NOTI_WEBHOOK` 미설정이면 webhook 백엔드만 silent no-op이 되고 다른 백엔드는 정상 동작한다.

### 7. 명령별로 알림 받기/안 받기

명시 `bell` 호출은 skip-list와 무관하게 항상 발사. 즉 `vim` 이 skip 목록에 있어도:

```
$ bell vim file.c                     # 알림 받음 (명시 의도)
```

### 8. 에이전트/스크립트에서는 알림 안 옴

LLM 에이전트의 `bash_tool`, `./script.sh` 내부의 sub-shell, `ssh host 'cmd'` 등은 모두 non-interactive bash다. bell-bash가 source되어도 `[[ $- != *i* ]]` 가드에서 silent return하므로:

- 자동 hook (PS0/PROMPT_COMMAND) — 설치되지 않음
- `bell` 함수 — 정의되지 않음 (command not found)
- `bell_skip` 함수 — 정의되지 않음

이는 의도된 동작. 별도 환경변수 toggle 없이 단일 unfix point로 모든 비-interactive 컨텍스트가 자동 제외된다.

### 9. installer가 기존 `.tmux.conf` 충돌을 발견했을 때

```
$ ./install
[bell-bash] Detected pre-existing 'monitor-bell off' / 'visual-bell off' in /home/j/.tmux.conf.
[bell-bash] tmux uses last-write-wins, so our block at the end will override these.
Comment out the conflicting lines so the override is obvious? [y/N]
```

- **y**: 충돌 라인이 `# [bell-bash] commented out:  <원본>` 으로 prefix됨. 백업은 따로 잡혀있음.
- **N** (default): 원본 그대로 두고 우리 블록을 끝에 append. tmux는 마지막에 평가된 설정을 쓰므로 실제 동작은 동일하지만 conf 파일을 읽었을 때 "왜 두 줄이 다른 말을 하는지" 헷갈릴 수 있다.

---

## 트러블슈팅

### "알림 메시지의 명령 텍스트가 이상해요" (HISTCONTROL)

```bash
HISTCONTROL=ignorespace
 long_running_cmd            # ← 선행 공백
```

선행 공백으로 시작하는 명령은 history에 안 들어간다. 자동 trigger의 알림 body는 `history 1` 에서 명령 텍스트를 가져오는데, 위 케이스에서는 직전 history entry (= 다른 명령) 가 표시되어 부정확하다. 시간 측정은 정확하다.

회피: `HISTCONTROL` 에서 `ignorespace` 빼기, 또는 명시적 `bell <cmd>` 사용.

### GUI 세션이 아닌데 notify-send 백엔드를 enable했어요

`notify-send` 자체는 PATH에 있더라도 dbus / GUI 세션이 없으면 실패한다. bell-bash는 이 실패를 silent로 처리하므로 다른 백엔드 (bel/webhook) 는 정상 동작한다. notify-send를 backends 목록에서 빼고 싶으면:

```bash
# .bashrc 의 bell-bash 블록 안에서
export BELL_BASH_BACKENDS='bel,webhook'
```

### tmux 설정이 안 먹어요

기존 세션은 이전 conf를 사용 중이다. `tmux source-file ~/.tmux.conf` 로 다시 로드하거나, 새 tmux 세션을 시작.

### 다른 PROMPT_COMMAND (starship 등) 와 충돌이 의심돼요

bell-bash는 source 시점의 기존 `$PROMPT_COMMAND` 를 `__bell_bash_prev_pc` 에 보존하고, 우리 wrapper 안에서 원래 `$?` 를 복원한 뒤 호출한다. starship의 status indicator 가 정상 동작해야 한다.

문제가 의심되면:

```bash
$ echo "$PROMPT_COMMAND"                   # __bell_bash_prompt_command
$ echo "$__bell_bash_prev_pc"              # 이전 PROMPT_COMMAND
```

starship를 bell-bash *뒤에* 설치하면 starship이 우리 hook을 덮어쓴다. 순서: bell-bash 마지막에 source (install이 자동으로 .bashrc 끝에 append하므로 보통 OK).

### bash 4.x 환경에서 source했어요

`bell` 라이브러리는 `$EPOCHREALTIME` (bash 5.0+) 의존. 4.x에서는 source 즉시 silent return이라 hook도 함수도 설치되지 않는다. 시스템에 bash 5+ 가 있으면 `$SHELL` 을 그쪽으로 가리켜야 한다.

### `bell_skip += foo | grep bar` 가 동작 안 해요

```bash
$ bell_skip += foo | grep bar
```

pipe 의 좌측은 subshell에서 실행되므로 `BELL_BASH_SKIP_LIST` 변경이 subshell scope에 갇혀 사라진다. (의도된 한계.) skip-list 변경은 직접 호출만:

```bash
$ bell_skip += foo
$ bell_skip | grep bar
```

---

## FAQ

**Q. `bell` 과 `bel` 의 차이?**

`bell` 은 사용자가 직접 호출하는 셸 함수 (`bell make`, `cmd; bell`). `bel` 은 env var 값 (`BELL_BASH_BACKENDS=bel,...`)에서 BEL 제어 문자 백엔드를 가리키는 내부 식별자. 한 글자 차이지만 역할이 다르다.

**Q. 백그라운드 job 알림 (`long_thing &`) 은?**

v0.1 비지원. 별도 메커니즘이 필요해 future work.

**Q. zsh 지원?**

v0.1 비지원. `preexec` / `precmd` 가 있어 port 가능하지만 future work.

**Q. macOS?**

v0.1 비지원. `notify-send` 대신 `terminal-notifier` 같은 별도 백엔드가 필요. future work.

**Q. `NOTI_WEBHOOK` 을 dotfiles repo에 커밋해도 되나?**

**안 됨.** webhook URL 은 그 자체가 credential 이다. 공개 repo에 커밋되면 누구나 메시지를 보낼 수 있다. `~/.bashrc` 안에 두되 git ignore 하거나, 별도 untracked file (예: `~/.config/bell-bash/env`) 에서 export 하고 그 파일을 dotfiles repo 밖에 둘 것.

**Q. 알림 rate limit (5초 내 중복 발사 억제) 은?**

v0.1 비지원. future work. 임계값을 올려서 우회 가능.
