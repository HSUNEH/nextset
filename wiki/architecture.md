---
type: architecture
status: active
updated: "2026-07-24"
tags: [architecture, state-machine, persistence, live-activity]
sources:
  - Package.swift
  - project.yml
  - Sources/DamSetCore/WorkoutEngine.swift
  - Sources/DamSetCore/LiveActivitySupport.swift
  - DamSetApp/WorkoutViewModel.swift
  - DamSetLiveActivity/WorkoutIntents.swift
---

# 시스템 구조

## 타깃 경계

```text
DamSetApp (SwiftUI + WorkoutViewModel)
        │
        ├── DamSetCore (모델, 상태 머신, 저장, 분석, 동기화)
        │
        └── DamSetLiveActivity (WidgetKit 표시)
                  │
                  └── WorkoutIntents도 앱 타깃에 함께 컴파일
```

- `DamSetCore`는 UI와 분리된 정규 모델·상태 전이 계층이다.
- `DamSetApp`은 화면과 `@MainActor` 조정을 담당하고 직접 상태 규칙을
  복제하지 않는다.
- `DamSetLiveActivity`는 표시와 App Intent를 제공한다. Intent 구현은 앱
  프로세스에서 같은 세션 변경 파이프라인을 쓰도록 앱 타깃에도 포함된다.
- SwiftPM은 코어 테스트, 스모크 실행, macOS 앱 셸을 제공한다. XcodeGen의
  `project.yml`은 실제 iOS 앱·프레임워크·확장 타깃의 원본 설정이다.

## 정규 세션

`WorkoutRoutineSession`이 진행 중 운동의 단일 정규 상태다.
`lockScreenState`는 앱과 Live Activity가 함께 사용하는 현재 수행량과
표시 상태를 담는다. 세트 완료 시 `WorkoutEngine`이 이 정규 수행량으로
`CompletedSet`을 만든다.

주요 상태:

```text
active / performingSet
  └─ completeCurrentSet
       ├─ 다음 세트 있음 → resting
       │                    └─ 만료 또는 명시적 건너뛰기 → active
       └─ 마지막 세트 → completed
```

휴식 중 횟수·시간·무게 보정은 방금 완료한 `CompletedSet`과
`lockScreenState`를 같이 바꾼다. 운동 종류나 추적 단위가 맞지 않으면
엔진이 전이를 거부한다.

## 변경 파이프라인

일반 세션 변경은 반드시 아래 순서를 통과한다.

```text
WorkoutEngine으로 메모리 복사본 변경
→ ActiveSessionStore에 저장
→ 휴식 종료 알림 예약/취소
→ Live Activity 시작·갱신·종료
→ 성공 후 화면 상태 반영
```

`WorkoutSessionSync.applyDidChange`와 내부 mutation gate가 이 순서를
직렬화한다. 빠른 App Intent 탭도 `LockScreenActionCoordinator`가 전체
load → mutate → save 주기를 직렬화하며, `sessionId`를 비교해 오래된
activity의 변경을 무시한다.

단순 진행량 보정은 `applyProgressCorrection` 경로를 사용할 수 있지만,
휴식 만료처럼 상태 단계가 바뀌었으면 전체 `applyDidChange`를 사용해야 한다.

세트 완료는 저장이 성공하기 전 UI를 휴식/완료로 바꾸지 않는다. 이 순서를
바꾸는 변경은 데이터 손실 위험이 높다.

## 시간과 휴식

휴식의 기준은 `restRemainingSeconds`를 1초씩 감소시키는 카운터가 아니라
`resumeAt` 절대 시각이다. 화면 갱신이나 프로세스 중단 뒤에도 현재 시각과
마감 시각의 차이로 남은 시간을 복구한다. 남은 시간이 0이면 엔진은 다음
세트를 시작하는 현재 정책을 따른다.

휴식 종료 전달은 두 경로다.

- 포그라운드: `InAppRestCuePlayer`가 짧은 결합 음원과 햅틱을 재생하고
  다른 오디오는 duck 후 복구한다.
- 잠금/백그라운드: iOS 26에서 Live Activity가 허용되면
  `WorkoutSessionSync`가 `resumeAt`에 다음 세트 Activity를 예약 시작하고,
  현재 휴식 카드는 같은 시각에 종료한다. 시스템이 예약을 받아들인 경우 그
  Activity의 시작 알림음이 종료 신호를 담당하므로 중복 로컬 알림은 취소한다.
  예약할 수 없는 경우 `RestCueScheduler`가 `resumeAt`에 맞춰 로컬 알림을
  예약하는 폴백이다. 이 전환은 서버나 앱 깨우기에 의존하지 않는다.
- 휴식 ±30초 조정: pending 예약 카드는 생성 당시 마감을
  `ContentState.scheduledStart`에 새겨 두고, 갱신 때 세션 `resumeAt`과 1초
  이상 어긋나면 취소 후 재예약한다. 이미 종료된(zombie) 휴식 카드는 내용을
  바꿀 수 없으므로 즉시 dismiss하고 새 휴식 카드를 요청해 새 마감으로
  교체한다. 조정은 앱 포그라운드에서만 발생하므로(잠금 화면에 ±30 컨트롤
  없음) 즉시 요청이 허용된다.
- pending 카드 수명: 예약 알림음은 카드 시작에 묶여 있으므로, 세션이
  휴식을 벗어나면(다음 세트 조기 시작, 휴식 0초 단축, 세트 undo) 일반 갱신
  경로에서 pending 카드를 반드시 `end(nil, .immediate)`로 취소한다.
  취소하지 않으면 옛 마감 시각에 유령 시작 알림음이 그대로 울려 휴식
  종료음이 두 번 들린다.

## 저장

- 진행 세션: `ActiveSessionStore`
- 완료 요약: `LocalWorkoutStore`
- 사용자 루틴: `RoutineTemplateStore`
- 형식: 로컬 JSON

스토어는 가능한 공유 컨테이너를 사용하고 사용할 수 없으면 앱 로컬
컨테이너로 폴백한다. 현재 무료 개발 팀 설정에서는 App Group entitlement가
없으므로 앱 로컬 컨테이너가 실제 기본 경로다. 저장 형식 변경은 기존 JSON
호환성과 재실행 복원을 테스트해야 한다.

## 변경 시 결합 지점

- 세션 모델 필드 추가: 모델, 엔진 전이, JSON 디코딩 호환성, Live Activity
  content state, App Intent, 요약/분석, 스모크와 단위 테스트를 함께 확인한다.
- 새 수행 단위 추가: `trackingMode`, 편집 UI, 휴식 중 보정, 완료 기록,
  위젯 표시, 볼륨/분석 의미를 함께 확인한다.
- 휴식 정책 변경: 엔진의 벽시계 계산, ViewModel tick, 알림 예약,
  Live Activity의 자체 갱신 표현을 함께 확인한다.
- 프로젝트 타깃 변경: `project.yml`을 먼저 바꾸고 Xcode 프로젝트를
  재생성한다.

관련 결정: [정규 세션 ADR](decisions/0001-canonical-session-sync.md),
[프로젝트 생성과 서명 ADR](decisions/0002-project-generation-and-signing.md).
