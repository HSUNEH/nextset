---
type: playbook
status: active
updated: "2026-07-19"
tags: [device, simulator, live-activity, signing]
sources:
  - docs/install.md
  - docs/qa-automation.md
  - project.yml
  - DamSetLiveActivity/WorkoutIntents.swift
last_verified: "2026-07-19"
---

# 기기와 Live Activity QA

이 페이지의 환경 상태는 2026-07-19에 마지막으로 확인됐다. 도구 버전과
연결 기기는 바뀔 수 있으므로 작업 시작 때 명령으로 재확인한다.

## 현재 알려진 환경

- `/Applications/Xcode.app`의 마지막 확인 버전: Xcode 26.6
- 현재 전역 `xcode-select`는 Command Line Tools를 가리킨다. Xcode
  라이선스 동의 뒤에는 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  접두사로 Xcode 26.6과 `devicectl`을 사용할 수 있다.
- iOS 플랫폼은 Xcode Settings의 Components에서 설치한다. 이번 환경에서
  항목 이름은 `iOS 26.5.1 + iOS 26.5 Simulator`이고 8.49GB를 사용한다.
  이 Components 패키지는 실기기 지원에도 필요하다. 반면
  `xcodebuild -downloadPlatform iOS`는 약 7.9GB의 독립 Simulator Runtime을
  받아 이 문제를 해결하지 않는다.
- 연결된 iPhone은 `devicectl`에서 `connected`로 확인된다. Xcode 대상
  목록에 실기기가 즉시 보이지 않아도 generic iOS 빌드 뒤
  `devicectl device install app`과 `process launch`로 설치·실행할 수 있다.
- 연결된 iPhone은 iPhone Mirroring에서 DamSet 실행과 화면 캡처가
  확인됐다. 실기기 UI를 읽을 때 현재 가장 빠른 관찰 채널이다.
- 무료 개발 팀으로 앱과 Live Activity 확장을 서명하기 위해 App Group
  entitlement를 제거한 상태다.
- 자동 프로비저닝에는 Xcode Settings의 Accounts에 Apple 개발 계정이
  등록돼 있어야 한다. generic iOS 빌드에는
  `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`을 쓴다.
- 스토어는 App Group을 사용할 수 없으면 앱 로컬 컨테이너로 폴백한다.
- 무료 팀 프로파일은 짧게 만료되므로 실기기 설치 전 재서명이 필요할 수 있다.

현재 사실은 반드시 아래로 다시 확인한다.

```bash
xcode-select -p
xcodebuild -version
xcodebuild -project DamSet.xcodeproj -scheme DamSet -showdestinations
xcrun devicectl list devices
```

전역 선택이 Command Line Tools이면 명령 앞에 아래 환경값을 붙일 수 있다.
단, 라이선스 동의 자체를 우회하지는 않는다.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
```

## 시뮬레이터를 쓸 때

적합:

- 실제 iOS 앱과 확장 컴파일
- 알림 권한 프롬프트와 로컬 알림 도착
- Live Activity 레이아웃과 시간 표시
- 잠금 화면 Intent의 세션 보정·완료·다음 세트 흐름
- 앱 재진입 시 공유 세션 채택

부족:

- 햅틱의 물리적 품질
- 음악 재생 유지와 오디오 duck 복구
- 실제 기기 잠금/Focus/무음 모드의 최종 경험

테스트할 때는 수행 중, 휴식 중, 휴식 만료, 완료의 각 단계를 관찰한다.
오래된 Activity가 남은 상태에서 새 세션을 시작해 `sessionId` 보호도 확인할
가치가 있다.

## 실기기를 쓸 때

사전 조건:

- 기기 잠금 해제, Mac 신뢰, Developer Mode
- Xcode에서 유효한 Team과 프로비저닝
- 첫 실행 뒤 개발자 프로파일 신뢰
- Live Activity와 알림 권한 허용

관찰 순서:

1. 음악 앱에서 재생을 시작한다.
2. DamSet에서 루틴을 시작하고 실제 수행량을 바꾼다.
3. 세트를 완료하고 휴식, `resumeAt`, Live Activity를 확인한다.
4. 기기를 잠그고 Activity의 운동명·세트·수행량·남은 시간·컨트롤을 본다.
5. 잠금 화면에서 값을 빠르게 여러 번 조절하고 앱 재진입 뒤 같은지 확인한다.
6. 휴식 종료 시 기존 휴식 카드가 사라지고 예약된 다음 세트 카드가 나타나는지,
   그리고 시작 알림음과 음악 재생 유지 여부를 기록한다. 이 전환은 앱을 열지
   않은 잠금 상태에서도 확인한다.
7. 마지막 세트를 완료하고 History와 재실행 복원을 확인한다.

## 설치 문제 분류

- `Developer Mode disabled`: 개발 채널 접근 후 기기에서 Developer Mode를
  켜고 재부팅한다.
- DDI/OS 지원 오류: Xcode와 기기 OS 지원 범위를 확인하고 기기를 잠금
  해제한 뒤 다시 마운트한다.
- `iOS <version> is not installed`: Xcode Settings의 Components에서 기기
  OS용 iOS 플랫폼을 설치한다. Components 항목에 Simulator가 함께 표시될 수
  있지만 실기기 지원 패키지이므로 제거하지 않는다. 반면
  `xcodebuild -downloadPlatform iOS`로 받은 독립 Simulator Runtime만
  `xcrun simctl runtime list`에서 비중복인지 식별한 뒤 제거한다.
- App Group capability 오류: 현재 무료 팀 결정과 `project.yml`을 확인한다.
  임의로 entitlement를 되살리지 않는다.
- remote launch `Locked`: 기기를 잠금 해제한다.
- 프로파일 만료: 동일 팀으로 다시 빌드·설치한다.

정확한 headless 설치 명령과 과거 해결 과정은 `docs/install.md`, 이미 실행한
상세 QA는 `docs/qa-automation.md`에 있다. 이 페이지에는 다음 시도에 영향을
주는 절차만 유지한다.
