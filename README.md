# DamSet

DamSet is an iPhone-first workout routine MVP for managing sets, rest timers, and workout records with a lock-screen-friendly training flow.

## Product goal

Build an iPhone SwiftUI app where users can configure a workout routine in the app, then manage live set progress from the iPhone Lock Screen with quick reps adjustment, set completion, rest countdown, and restart cues.

## MVP scope

### In the app

- Configure pre-workout routines
- Set target weight
- Set target reps
- Set rest duration between sets
- Review and save final workout records

### On the Lock Screen / Live Activity

- Show current set target reps
- Adjust actual completed reps with `- / +`
- Mark the set as complete
- Start the rest timer after set completion
- Show remaining rest time and next-set restart time
- Explicitly skip rest or start the next set when ready
- Notify the user near rest completion

### Rest completion cue

Target experience:

- 3 seconds before rest ends: `3, 2, 1, horn`
- The cue should be audible while workout music continues, where iOS policy and APIs allow it.
- If iOS lock-screen/background audio constraints prevent the ideal cue, the MVP may fall back to notification sound + haptics while preserving the rest-timer flow.

## Rest cue and iOS audio behavior

Implemented behavior (two paths, selected by app state):

- **App in foreground (ideal cue)** — `InAppRestCuePlayer` drives the rest tick: at 3/2/1 seconds remaining it speaks the number (`AVSpeechSynthesizer`) with a medium haptic, and at 0 it plays a horn system sound with a success haptic. The audio session uses `.playback` + `.duckOthers` and deactivates with `.notifyOthersOnDeactivation`, so workout music keeps playing (ducked during the cue) and returns to full volume afterwards.
- **App backgrounded / iPhone locked (fallback: `notificationSoundAndHaptics`)** — iOS does not allow a backgrounded app to play arbitrary countdown audio on the Lock Screen. `RestCueScheduler` therefore schedules four local notifications at `resumeAt - 3s / -2s / -1s / 0s` titled `3`, `2`, `1`, `Next set — go!` with the default notification sound (vibration follows the user's sound/haptics settings). Advancing to the next set early or ending the workout cancels the pending cue notifications.

Music playback test procedure (run on a real iPhone):

1. Play music in Apple Music or Spotify and confirm the Now Playing state is `playing`.
2. Start a routine in DamSet and complete a set; leave the app in the foreground for the ideal-cue path, or lock the iPhone for the fallback path.
3. Observe the final 3 seconds of rest: expect `3, 2, 1, horn` (spoken + haptics in foreground; notification sounds when locked).
4. After the cue, verify the music is still playing (ducking must recover in the foreground path; notification sounds never stop music playback).

Observed results:

- **2026-07-03, iPhone 17 Pro simulator (iOS 26.3.1)** — fallback path verified
  while locked: the Live Activity countdown reached 0:00 and the notification
  stack delivered all four cues (`3`, `2`, `1`, `Next set — go!` with the
  upcoming exercise name). See `docs/qa-automation.md` layer 3 for the full run.
- Foreground ideal cue (spoken 3-2-1 + horn + haptics over ducked music) and
  `playbackStateBeforeCue` / `playbackStateAfterCue` with a real music app are
  **pending real-device QA** — the simulator cannot exercise audio
  ducking/haptics meaningfully. Record device observations here.

Fallback conditions:

- The fallback path is used whenever the app process cannot run the in-app cue at rest end: iPhone locked, app backgrounded or terminated, or Focus/notification permission denials preventing sound. If device QA shows the foreground path pausing music (`playbackStateAfterCue != playing`), ship with `fallbackMode = notificationSoundAndHaptics` and record the reason, per the seed spec.

## Initial platform decision

- iPhone-only iOS app
- SwiftUI-first native Apple design
- iOS 26.0+ deployment target
- Apple Watch, iPad, and macOS are deferred

## Design reference

Use Apple’s official design resources and Human Interface Guidelines:

- https://developer.apple.com/design/resources/

## Deferred

- Apple Watch app or Watch-specific controls
- iPad/macOS versions
- Custom routine builder beyond MVP-level setup
- AI coaching
- Diet tracking
- Social features
- Wearable integrations beyond future Apple Watch exploration


## Current implementation scaffold

This repo now contains a testable Swift core plus iOS app/Live Activity source scaffolding:

- `Package.swift` — SwiftPM package for `DamSetCore` and core tests.
- `Sources/DamSetCore/` — routine catalog, planned/completed sets, workout session state, lock-screen state, rest cue policy, summary calculation, and local-store protocol with in-memory and JSON-file (`FileWorkoutStore`) implementations. Actual reps and weight live in one canonical session state shared by the app and Live Activity.
- `Sources/DamSetCoreSmoke/` — executable smoke verification for default routines, reps adjustment, set completion, rest transitions, manual session-scoped sets, audio fallback policy, actual-weight override, full-session summary invariants, and file-store round-trip. `XcodeTests/DamSetCoreTests/` keeps XCTest coverage for full Xcode environments.
- `DamSetApp/` — SwiftUI iPhone app for routine selection and active workout flow: 1 Hz rest countdown tick, actual-weight editing during a set, session-scoped set repeat, end-workout confirmation (full-screen cover so the session can't be swiped away), workout summaries persisted via `FileWorkoutStore`, and a History section with a per-set final record screen.
- `DamSetLiveActivity/` — ActivityKit widget for the Lock Screen / Dynamic Island: target reps centered with `- / +` actual reps adjustment and set completion via `LiveActivityIntent` (runs in the app process against the shared App Group session store), a self-updating rest countdown (`Text(timerInterval:)`), and resume-at time. The Live Activity starts when a workout starts, updates on every state change, and ends with the session.
- `ActiveSessionStore` holds the in-flight session, `FileWorkoutStore` holds saved summaries, and `WorkoutSessionSync` applies one shared side-effect pipeline (persist → schedule/cancel rest cues → sync Live Activity). Free-team device builds use the app-local container; restore the App Group entitlements for separate-process sharing on a paid team.
- `docs/design-notes.md` — Apple HIG checklist plus Rest cue and iOS audio behavior test policy.
- `DamSet.xcodeproj` / `project.yml` — Xcode project generated with XcodeGen for iOS app, core framework, and Live Activity extension targets.
- `docs/qa-automation.md` — layered QA plan for core tests, Xcode builds, simulator checks, real iPhone install, iPhone Mirroring/QuickTime screen-observed QA, and Lock Screen/Live Activity validation.
- `docs/install.md` — Xcode setup, simulator run, and real iPhone install guide.

### Local verification

The verified local gate is:

```bash
swift test
swift run DamSetCoreSmoke
xcodebuild test -project DamSet.xcodeproj -scheme DamSet -destination 'platform=iOS Simulator,name=iPhone 16e,OS=26.3'
ruby -e 'require "yaml"; YAML.load_file("seed.yaml"); puts "seed yaml ok"'
git diff --check
```
