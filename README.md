# CCUsage Widget

Claude Code와 Codex의 **남은 사용 한도**를 macOS 알림 센터·바탕화면 위젯으로 보여줍니다.
Xcode 프로젝트 없이 `swiftc` + Command Line Tools 만으로 빌드하는 WidgetKit 확장입니다.

<!-- TODO: 스크린샷 -->

## 보여주는 것

| 제품 | 한도 |
|---|---|
| Claude Code | 세션(5시간) · 주간 전체 · 주간 모델별 |
| Codex | 세션(5시간) · 주간 전체 |

남은 비율과 리셋 시각(24시간 표기)을 함께 표시하고, 사용률 75%를 넘으면 주황, 90%를 넘으면 빨강으로 바뀝니다.
Large 크기에서는 Claude Code의 일별 사용량과 모델별 토큰·비용 추정치도 함께 보여줍니다.

## 데이터 출처

한도 값은 서버가 주는 값이라 로컬 로그만으로는 알 수 없습니다. 두 제품이 서로 다릅니다.

- **Claude Code** — `claude -p "/usage"` 출력을 파싱합니다. 호출에 약 4초 걸려 5분 TTL 캐시를 둡니다.
- **Codex** — `~/.codex/sessions/**/*.jsonl` 에 API 응답의 `rate_limits` 가 그대로 남아 직접 읽습니다 (약 0.03초).
- **토큰·비용 추정치** — `~/.claude/projects/**/*.jsonl` 의 `usage` 필드를 집계합니다. 공개 API 단가 기준 **추정치**이며 실제 청구액이 아닙니다. 구독제라면 "같은 양을 API로 썼다면 얼마"에 해당합니다.

위젯 확장은 샌드박스라 위 경로를 직접 읽지 못합니다. 그래서 메뉴 막대 앱(비샌드박스)이 60초마다 집계해
App Group 컨테이너에 스냅샷을 쓰고, 위젯은 그 스냅샷만 읽습니다.

```
메뉴 막대 앱 ──(collect.py)──> ~/.claude, ~/.codex
      │
      └──> App Group: <TeamID>.group.local.ccusage/snapshot.json
                              │
                              └──> 위젯 확장 (샌드박스)
```

## 요구 사항

- macOS 14 이상 (실측·검증은 macOS 26)
- Xcode (SDK와 **Apple Development 인증서** 때문에 필요 — 무료 Apple ID로 충분)
- `claude` CLI (Claude Code 한도용), `codex` CLI (Codex 한도용) — 없으면 해당 제품 칸만 비고 나머지는 동작

## 설치

```sh
./build.sh
open -a /Applications/CCUsage.app
```

바탕화면 우클릭 → **위젯 편집…** → `CCUsage` 검색 → 원하는 크기를 끌어다 놓습니다.

제거는 `./uninstall.sh`.

## 빌드가 하는 일

`build.sh` 는 Xcode 프로젝트 없이 앱 번들과 위젯 확장을 직접 조립합니다.

1. 키체인에서 `Apple Development` 인증서를 찾아 Team ID를 추출 → App Group 이름을 `<TeamID>.group.local.ccusage` 로 맞춤
2. `CFBundleVersion` 을 빌드 시각 타임스탬프로 지정
3. Xcode SDK 로 위젯 확장과 앱을 컴파일
4. 아이콘 생성, 스크립트를 번들 Resources 에 복사
5. 안쪽(확장) → 바깥(앱) 순서로 서명
6. LaunchServices / PlugInKit 에 등록

### 직접 조립할 때 걸렸던 것들

같은 방식으로 만드시려는 분을 위해 남깁니다. 넷 다 없으면 위젯이 갤러리에 아예 안 뜹니다.

| 항목 | 없으면 |
|---|---|
| **`-Xlinker -e -Xlinker _NSExtensionMain`** | Swift `@main` 이 만든 일반 `main` 으로 진입해 ExtensionFoundation 이 확장 타입을 판정하지 못하고 프로세스가 즉사합니다. chronod 로그에는 `unable to obtain widget extension session` 으로만 남습니다. |
| **`com.apple.security.app-sandbox` 엔타이틀먼트** | `pluginkit` 등록조차 되지 않습니다. |
| **빌드마다 증가하는 `CFBundleVersion`** | chronod 가 `Unchanged extension` 으로 판단해 위젯 디스크립터를 다시 가져오지 않습니다. |
| **App Group** | 샌드박스인 위젯이 앱이 만든 스냅샷을 읽을 방법이 없습니다. |

Team ID 없는 ad-hoc 서명으로도 등록까지는 되지만, 인증서가 있으면 `build.sh` 가 알아서 씁니다.

## 구조

```
build.sh            앱 + 위젯 확장 조립·서명·등록
uninstall.sh        전체 제거
collect.py          JSONL 집계 + 한도 통합 (파일별 mtime 캐시)
limits.py           Claude Code 한도 (`claude -p /usage` 파싱)
codex.py            Codex 한도 (rollout jsonl 의 rate_limits)
src/Shared.swift    앱·위젯이 함께 쓰는 모델과 표기 헬퍼
src/App/            메뉴 막대 앱 + 바탕화면 패널(위젯 대체용)
src/Widget/         WidgetKit 확장 (small / medium / large)
src/makeicon.swift  앱 아이콘 생성
```

## 설정

- 단가표는 `collect.py` 의 `PRICES` 에 있습니다.
- 한도 조회 주기는 `limits.py` 의 `TTL`(기본 300초).
- 집계 보관 기간은 `collect.py` 의 `RETAIN_DAYS`(기본 45일).
