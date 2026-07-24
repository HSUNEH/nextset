---
type: log
status: active
updated: "2026-07-24"
tags: [agent-wiki, work-log]
---

# 작업 로그

완료된 의미 있는 작업을 오래된 순서에서 최신 순서로 끝에 추가한다. 상세
지식은 종합 페이지와 ADR에 두고 여기에는 범위, 행동, 결정, 실제 검증만
기록한다.

## [2026-07-19] setup | 에이전트 LLM 위키 초기화

- Scope: 저장소 전역 에이전트 계약과 제품·구조·도구·검증·기기 QA·결정 페이지를 만들고 README에서 위키로 진입할 수 있게 했다.
- Actions: Karpathy의 LLM Wiki 패턴을 근거/위키/운영 3계층으로 적용하고, 현재 코드·문서·Git 이력에서 초기 지식을 종합했다. 상대 링크와 frontmatter를 검사하는 로컬 lint를 추가했다.
- Decisions: 코드·테스트·설정·실행 결과를 원본 근거로 유지하고 별도 raw 복제는 만들지 않는다. 모든 의미 있는 작업은 전·중·후 위키 루프와 append-only 완료 로그를 따른다.
- Verification: `ruby Scripts/check_agent_wiki.rb` 통과(11 pages), `ruby -c Scripts/check_agent_wiki.rb` 통과, `git diff --check` 통과.
- Wiki: `wiki/index.md`, `wiki/schema.md`, `wiki/product.md`, `wiki/architecture.md`, `wiki/tools.md`, `wiki/playbooks/`, `wiki/decisions/`

## [2026-07-19] docs | 실기기 화면 기반 README 히어로 교체

- Scope: 연결된 iPhone의 실제 DamSet 루틴·준비·운동·휴식 화면을 확인하고 `docs/assets/damset-hero.jpg`를 현재 휴식 UI 기반 이미지로 교체했다.
- Actions: iPhone Mirroring을 Computer Use로 조작해 실제 화면을 캡처하고 캡처용 운동은 저장하지 않고 폐기했다. 기존 히어로를 구도·분위기 참조로, 실제 휴식 화면을 UI 참조로 사용해 built-in image generation으로 합성한 뒤 JPEG로 변환했다.
- Decisions: 바벨 중심의 어두운 체육관 구도는 유지하고, 허구의 녹색 원형 대시보드 대신 실제 검정 금속 패널·적색 `01:30` 휴식 화면과 적색 실내 조명을 사용한다.
- Verification: 실기기에서 원본 UI 관찰, 최종 이미지 육안 확인, JPEG `1672×941` 확인, `ruby Scripts/check_agent_wiki.rb`와 `git diff --check` 통과.
- Wiki: `wiki/product.md`, `wiki/tools.md`, `wiki/playbooks/device-live-activity.md`

## [2026-07-19] decision | Orca 터미널은 CLI로 제어

- Scope: Orca 작업공간에서 Codex 분할을 만들 때의 도구 선택 기준을 기록했다.
- Actions: 설치된 `orca` CLI의 terminal 명령과 런타임 준비 상태를 확인하고 cmux의 명시적 대상 제어 방식과 대조했다.
- Decisions: `orca terminal list`로 핸들을 먼저 식별하고 `terminal split --command "codex"`로 새 분할에 직접 실행한다. Orca 런타임이 준비되지 않았을 때는 Computer Use로 패널을 조작하지 않는다.
- Verification: `orca terminal --help`, `orca terminal create --help`, `orca terminal split --help`, `orca status --json` 통과(runtime ready).
- Wiki: `wiki/tools.md`, `wiki/log.md`

## [2026-07-19] qa | 실기기 설치 전제 조건 재확인

- Scope: 연결된 iPhone에 최신 main을 설치하려는 실기기 QA의 도구체인·기기·저장 공간 조건을 재확인했다.
- Actions: Xcode 26.6 라이선스 동의 뒤 `DEVELOPER_DIR`로 `devicectl`과 대상 목록을 확인했다. iPhone은 인식됐지만 iOS 26.5 플랫폼 구성요소가 없어 대상이 제외됐다. `xcodebuild -downloadPlatform iOS`가 7.9GB Simulator Runtime을 받는 것을 확인하고, 즉시 `simctl runtime delete`로 제거했다.
- Decisions: 실기기 OS 플랫폼 부재를 Simulator Runtime 다운로드로 해결하려 하지 않는다. Xcode Components에서 실제 기기 플랫폼을 확인하기 전에는 큰 다운로드를 시작하지 않는다.
- Verification: `xcrun devicectl list devices`에서 iPhone available, `xcodebuild -showdestinations`에서 iOS 26.5 미설치 확인, `xcrun simctl runtime list`에서 새 런타임 삭제 확인, 디스크 여유 4.6GiB 복구.
- Wiki: `wiki/playbooks/device-live-activity.md`

## [2026-07-19] qa | main 실기기 설치와 실행 확인

- Scope: 최신 main을 연결된 iPhone에 개발 서명으로 설치하고 첫 화면 렌더링을 확인했다.
- Actions: Xcode Components의 iOS 플랫폼 패키지를 설치하고, Xcode Accounts에 추가된 개발 계정으로 generic iOS 빌드를 자동 프로비저닝했다. `devicectl`로 앱을 설치·실행한 뒤 iPhone Mirroring에서 루틴 목록을 관찰했다.
- Decisions: Components의 `iOS 26.5.1 + iOS 26.5 Simulator`는 실기기 지원에도 필요한 패키지다. 별도 `xcodebuild -downloadPlatform iOS` Simulator Runtime과 혼동하지 않는다.
- Verification: generic iOS `xcodebuild ... build` 성공, `devicectl device install app` 성공, `devicectl device process launch` 성공, iPhone Mirroring에서 DamSet 루틴 목록 렌더링 확인.
- Wiki: `wiki/playbooks/device-live-activity.md`, `wiki/log.md`

## [2026-07-19] feature | 앱 편집과 잠금 화면 개선 통합

- Scope: `HSUNEH/앱-수정`과 `HSUNEH/수정`의 운동 흐름·세트별 목표·잠금 화면 제어 개선을 main에 병합했다.
- Actions: 두 작업 워크트리의 미커밋 변경을 각각 보존한 뒤 merge commit으로 통합하고, iOS 앱·코어·Live Activity 타깃을 generic iOS로 빌드해 연결된 iPhone에 덮어설치·실행했다.
- Decisions: 루틴은 공통 목표를 기본값으로 하되 세트별 무게·횟수 덮어쓰기를 허용한다. 잠금 화면의 빠른 조절은 전체 위젯 갱신 대신 숫자 전환만 보여야 한다.
- Verification: 두 브랜치 `git diff --check` 통과, 통합 `xcodebuild ... build` 성공, `devicectl device install app`과 `process launch` 성공.
- Wiki: `wiki/product.md`, `wiki/playbooks/device-live-activity.md`, `wiki/log.md`

## [2026-07-19] fix | 운동 화면 상단 정렬

- Scope: 짧은 운동 화면이 세로 중앙에 배치돼 제어 아래에 큰 빈 공간이 생기던 문제를 고쳤다.
- Actions: `ViewThatFits` 외부에 상단 정렬 프레임을 적용하고, 통합 iOS 빌드를 연결된 iPhone에 덮어설치·실행했다.
- Decisions: 화면 변형 선택 컨테이너는 자식 높이를 유지할 수 있으므로, 운동 제어 화면의 세로 기준점은 명시적으로 상단에 고정한다.
- Verification: generic iOS `xcodebuild ... build` 성공, `devicectl device install app`과 `process launch` 성공.
- Wiki: `wiki/log.md`

## [2026-07-19] feature | 휴식 종료 예약 Activity와 운동 제어 정리

- Scope: 운동 중 화면의 세트 여정·정보 배치·무게 조절을 다듬고, 휴식 종료 시 다음 세트 Live Activity를 시스템에 예약하도록 했다.
- Actions: 두 Orca 워크트리 변경을 main에 merge했다. iOS 26의 예약 Activity 시작 API로 휴식 카드 종료와 다음 세트 카드 시작을 같은 `resumeAt`에 맡기고, 예약 성공 시 중복 로컬 종료 알림을 취소했다. 앱·잠금 화면의 무게 조절을 1kg 단위로 통일했다.
- Decisions: 잠긴 상태의 다음 세트 전환은 서버나 앱 깨우기에 기대지 않고 ActivityKit 예약 시작을 우선하며, 예약 불가 시 기존 로컬 알림 경로를 유지한다.
- Verification: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test` 73개 통과, `xcrun swift run DamSetCoreSmoke` 통과, generic iOS `xcodebuild ... build` 성공, 연결 iPhone에 `devicectl device install app` 및 `process launch` 성공.
- Wiki: `wiki/product.md`, `wiki/architecture.md`, `wiki/playbooks/device-live-activity.md`, `wiki/log.md`

## [2026-07-24] feature | 예상 운동 시간과 완료 소요시간 표시

- Scope: 운동 선택 화면에 선택 토글과 연동되는 예상 소요시간을 추가하고, 완료 카드와 기록 상세에 시작–종료 시각과 총 소요시간을 추가했다.
- Actions: `WorkoutDurationEstimate`를 DamSetCore에 두어 세트당 30초(시간 기반 세트는 목표 시간) + 마지막 세트를 제외한 휴식 합으로 계산했다. `WorkoutSummary.elapsedSeconds`와 앱 쪽 `compactDurationText`/`workoutTimeRangeText` 포맷터를 추가했다. 새 코어 파일 때문에 `xcodegen generate`로 프로젝트를 재생성했다.
- Decisions: 예상치에서 마지막 세트의 휴식은 엔진이 실제로 건너뛰므로 합산하지 않는다. 손으로 수정한 기록이 종료 < 시작이 되어도 경과시간은 0으로 클램프한다. `.build` 캐시가 다른 경로(nextset)에서 생성된 채 남아 있으면 `swift test`가 SwiftShims 오류로 죽으므로 캐시를 지우고 재실행한다.
- Verification: `swift test` 81개 통과(신규 8개 포함), `swift run DamSetCoreSmoke` 통과, `ruby Scripts/check_agent_wiki.rb` 통과, `git diff --check` 통과, generic iOS Simulator `xcodebuild ... build` 성공. generic iOS 개발 서명 빌드 뒤 연결된 iPhone 11에 `devicectl device install app`·`process launch` 성공. 새 화면 요소의 육안 관찰은 사용자 확인에 맡김.
- Wiki: `wiki/product.md`, `wiki/log.md`

## [2026-07-24] fix | 휴식 ±30초 조정의 잠금 화면 반영

- Scope: 앱에서 휴식시간을 ±30초 조정해도 잠금 화면 카운트다운과 다음 세트 예약 시각이 옛 마감에 머무르던 문제를 고쳤다.
- Actions: `ContentState`에 `scheduledStart`를 추가해 pending 예약 카드가 자기 마감을 기억하게 했다. `scheduleNextSetActivityIfPossible`을 async 결과 enum(kept/scheduled/rescheduled/unavailable)으로 바꿔 마감이 어긋난 pending을 `end(nil, .immediate)`로 취소하고 재예약하며, 재예약 시 이미 종료된 휴식 카드를 dismiss하고 새 카드를 요청해 `.after(새 resumeAt)`으로 교체했다.
- Decisions: 이미 `end()`된 Live Activity는 내용·dismissal을 갱신할 수 없으므로, 휴식 마감 변경은 카드 교체로 처리한다. 마감 비교는 1초 허용 오차의 `scheduledStart` 스탬프로 하고, 스탬프 없는(구버전) pending은 항상 stale로 보고 교체한다. 즉시 Activity 요청은 조정이 앱 포그라운드에서만 발생한다는 전제에 기댄다.
- Verification: `swift test` 81개 통과, `swift run DamSetCoreSmoke` 통과, `ruby Scripts/check_agent_wiki.rb` 통과, `git diff --check` 통과, generic iOS `xcodebuild ... build` 성공, iPhone 11에 `devicectl device install app`·`process launch` 성공. 잠금 화면에서 ±30 조정 후 카운트다운·전환 시각·알림음의 육안/청각 확인은 사용자 QA로 남김.
- Wiki: `wiki/architecture.md`, `wiki/log.md`

## [2026-07-24] fix | 휴식을 벗어나도 살아남는 pending 예약 카드 취소

- Scope: 잠금 화면 휴식 종료 알림음이 시간차를 두고 두 번 울리던 문제를 고쳤다. 다음 세트를 조기 시작하거나 휴식을 0초로 줄이거나 세트를 undo해 세션이 휴식을 벗어나도, 옛 마감에 예약된 다음 세트 카드가 남아 그 시각에 유령 알림음을 울렸다.
- Actions: `updateLiveActivity`의 일반 갱신 경로에서 비휴식 세션의 pending Activity를 `end(nil, .immediate)`로 취소하게 했다. 휴식이 자연 만료돼 앱이 포그라운드에서 다음 세트로 전환하는 경우에도 같은 경로가 아직 시작 전인 카드를 취소해 인앱 큐와 카드 알림음의 중복도 줄인다.
- Decisions: 예약 카드의 시작 알림음은 "예약이 유효한 동안"만 의미가 있으므로, 세션 상태가 resting이 아니게 되는 모든 전이는 pending 카드 취소를 동반해야 한다. 이 불변 조건은 일반 갱신 루프에 두어 개별 전이 코드가 잊지 못하게 한다.
- Verification: `swift test` 81개(30+8+38+5) 통과, `swift run DamSetCoreSmoke` 통과, `git diff --check` 통과, generic iOS `xcodebuild ... build` 성공, iPhone 11 `devicectl device install app`·`process launch` 성공. 조기 시작 후 옛 마감 시각에 알림음이 안 울리는지는 사용자 QA로 남김.
- Wiki: `wiki/architecture.md`, `wiki/log.md`
