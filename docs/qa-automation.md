# NextSet QA automation plan

NextSet needs more than unit tests because the core product value lives on the iPhone Lock Screen: Live Activity controls, rest timers, haptics/audio, and interaction while music is playing.

## QA layers

### 1. Deterministic core tests

Purpose: verify workout state transitions without UI/device dependencies.

Current local gate:

```bash
swift build
swift run NextSetCoreSmoke
ruby -e 'require "yaml"; YAML.load_file("seed.yaml"); puts "seed yaml ok"'
git diff --check
```

Covers:

- Default routine catalog has at least 3 routines.
- Workout session starts from a routine.
- Actual reps can be adjusted and clamp at zero.
- Completing a set records `CompletedSet` and starts rest.
- Rest reaches ready state and advances to the next set.
- Manual sets are session-scoped and do not mutate reusable routine templates.
- Rest cue fallback is selected when ideal audio cannot preserve music playback.

### 1.5 macOS app-shell UI automation (no Xcode required)

The SwiftPM `NextSetAppShell` executable runs the real SwiftUI views on macOS
(iOS-only chrome falls back: full-screen cover → sheet; Live Activity,
notifications, and audio cues are no-ops). Drive it with Accessibility
(`osascript` System Events element clicks — AXPress works without stealing
focus) and verify with per-window screenshots (`screencapture -l <windowID>`).

**Executed 2026-07-03 — full workout flow PASSED on the macOS shell:**

- Routine list shows 3 default routines; History hidden while empty.
- Start Push Foundation → set screen shows exercise, Set 1/3, target reps 34pt+,
  target `60 kg × 8`, reps `- / +`, weight `±2.5`, Set Done — no scrolling.
- Reps 8→7 via `-`, weight 60→62.5 via `+2.5`.
- Set Done → rest state: countdown ticked in real time (observed 01:29 → 01:04),
  fixed "Ready at" resume time shown, weight controls hidden during rest.
- Next Set advanced (including early advance mid-rest).
- Final set → "Workout complete · 3 sets · 1,217.5 kg volume"
  (62.5×7 + 60×8 + 30×10 — actual-weight override included), Add Set disabled.
- History row appeared immediately; detail screen showed per-set weight×reps
  rows, total sets/volume, started/ended times.
- Summary JSON persisted to
  `~/Library/Group Containers/group.com.hsuneh.nextset/workout-summaries.json`
  (ISO-8601 dates); the active-session file was cleared on completion.
- Kill + relaunch → History still listed (persistence across restart).

Found & fixed during this run: `UNUserNotificationCenter` traps in unbundled
executables (guarded); icon-only `- / +` buttons lacked accessibility labels
(added in app + widget).

Not coverable on the shell: Live Activity rendering/intents, notification cues,
spoken countdown/horn/haptics, music ducking — layers 2–6 below.

### 2. Xcode/iOS build gate

Requires full Xcode selected:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

Then add/run gates:

```bash
xcodebuild -scheme NextSet -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme NextSet -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Purpose:

- Compile the real iOS app target.
- Compile the Widget Extension / Live Activity target.
- Run XCTest/UI tests where available.

### 3. Simulator UI automation

Useful for fast app-shell checks:

- Launch app.
- Pick a routine.
- Adjust reps.
- Complete a set.
- Verify rest view appears.
- Verify final summary after last set.

Limitation: simulator is not sufficient for haptic/audio (spoken countdown,
horn, ducking) or music-interruption behavior — those need a real device.
Live Activity rendering, lock-screen intents, and notification cues DO work
on the simulator (verified below).

**Executed 2026-07-03 — full Live Activity flow PASSED on iPhone 17 Pro
simulator (iOS 26.3.1, Xcode 26.3 via DEVELOPER_DIR, no global
xcode-select change):**

Technique: `xcodebuild -destination 'generic/platform=iOS Simulator'` build,
`simctl install/launch`, `simctl io booted screenshot` for verification, and
a CGEvent click helper mapping device-logical coordinates onto the Simulator
window for taps (System Events `click at` is blocked on modern macOS);
Device > Lock / Home driven via the Simulator menu bar.

- App launched; starting a routine triggered the notification-permission
  prompt (rest cues) and the lock-screen "Allow Live Activities?" prompt.
- Set screen matched the macOS-shell QA (target reps/weight, ±, Set Done);
  Set Done started rest with a ticking in-app countdown and resume time.
- Lock Screen showed the Live Activity: exercise, Set n/m, self-updating
  countdown (Text(timerInterval:) — no per-second activity updates), resume
  time, and the − / actual reps / + / Done controls.
- Rest-end cue fired while locked: notification stack (badge 4 = "3", "2",
  "1", "Next set — go!") appeared at resumeAt; the second round's final
  notification correctly named the upcoming exercise (Shoulder Press).
- Tapping + during an active rest was ignored (intent phase guard).
- After rest expired, one Done tap on the Lock Screen auto-advanced to the
  next set, recorded it, ended the workout, and the activity re-rendered as
  "Set 3/3 · Workout complete" — all without unlocking.
- Foregrounding the app picked up the intent-completed workout from the App
  Group store: "3 sets · 1,260 kg volume" (8×60 + 8×60 + 10×30 — exact),
  and History listed the record.
- Session survived an app reinstall mid-workout (shared-store adoption).

Found & fixed during this run: framework target needed
`GENERATE_INFOPLIST_FILE: YES` (build failed without it); widget hid the
−/+/Done controls during rest, violating the "all visible simultaneously"
acceptance criterion and leaving no lock-screen action after rest expired
with stale content (controls now always visible; mid-rest taps no-op).

Known cosmetic follow-ups: when a workout is completed from the Lock Screen,
the app's completed screen still shows the previous set header (totals are
correct); ended-activity header keeps the last exercise name.

### 4. Real iPhone install + logs

Requires:

- iPhone connected to Mac.
- “Trust This Computer” approved on iPhone.
- iPhone Developer Mode enabled.
- Apple signing team selected in Xcode.

Agent-visible checks:

```bash
xcrun xctrace list devices
xcrun devicectl list devices
```

Then install/run through Xcode or `xcodebuild` once project targets exist.

Purpose:

- Verify real install.
- Capture build/runtime logs.
- Detect crashes.
- Verify Live Activity permissions and behavior.

### 5. Screen-observed QA

The agent cannot see the iPhone screen directly unless the iPhone display is surfaced on the Mac or through an external camera/feed.

Preferred options:

1. **macOS iPhone Mirroring**
   - This Mac has `/System/Applications/iPhone Mirroring.app`.
   - If the mirrored iPhone window is visible on the Mac, the agent can use macOS screenshots to inspect it.
   - Best path for iterative visual QA if it exposes Lock Screen / app states reliably.

2. **QuickTime Player iPhone capture**
   - Connect iPhone by USB.
   - Open QuickTime Player → New Movie Recording → select iPhone as camera source.
   - If the QuickTime window is visible on Mac, the agent can screenshot/analyze the mirrored view.
   - Good fallback when iPhone Mirroring is limited.

3. **External camera pointed at iPhone**
   - Useful if Lock Screen, haptics, or physical-device behavior is not visible via software mirroring.
   - Camera feed must appear on the Mac as a window or capture device the agent can inspect.

### 6. Lock Screen / Live Activity manual-observed test script

Run on real iPhone:

1. Install and launch NextSet.
2. Start music playback in Music/Spotify/YouTube Music.
3. Start a default routine.
4. Lock iPhone.
5. Verify Live Activity shows:
   - exercise name
   - set index
   - target/actual reps
   - `- / +`
   - Set Done
   - rest remaining
   - resume-at time
6. Use `- / +` from Lock Screen and verify app state updates.
7. Tap Set Done and verify rest timer starts.
8. At T-3 seconds, observe cue:
   - ideal pass: `3, 2, 1, horn` is heard and music remains playing.
   - fallback pass: notification sound/haptics happen, music remains acceptable, and fallback reason is documented.
9. Continue until final summary is saved.

## Automation priority

1. Create Xcode project/targets so the app can install.
2. Add CLI build/install gates with `xcodebuild` and `devicectl`.
3. Add screen-observed QA harness using iPhone Mirroring or QuickTime window screenshots.
4. Add real-device checklist runner that records logs, screenshots, and pass/fail notes.
5. Only then tune Live Activity and audio/haptic behavior.

## Current blockers

- Full Xcode is not selected on this Mac; current `xcodebuild` fails because the active developer directory is Command Line Tools.
- Real iPhone build/install requires signing setup and a connected trusted iPhone.
- Final Lock Screen/audio behavior must be verified on physical device.
