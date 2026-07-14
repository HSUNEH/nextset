# DamSet install guide

## Current state

**Xcode 26.6 (17F113, iOS 26.5 SDK) is installed at `/Applications/Xcode.app`**
(App Store install on 2026-07-03, after this Mac was upgraded from Sequoia 15.7
to macOS 26.5.2 — that upgrade removed the old "App Store Xcode needs
macOS 26.2+" ceiling that had pinned the machine to Xcode 26.3). The global
`xcode-select` now points at full Xcode, so no `DEVELOPER_DIR` prefix is
needed anymore:

```bash
xcodebuild -version   # Xcode 26.6 (17F113)
```

The App Store build ships without the iOS platform; it was added with
`xcodebuild -downloadPlatform iOS` (iOS 26.5 simulator runtime + device
support, ~8.5 GB). Both the iOS 26.3.1 and 26.5 simulator runtimes are
installed, and the app has been rebuilt with the 26.6 toolchain and re-QA'd
on the simulator (see `docs/qa-automation.md`).

## One-time Mac setup

1. Install Xcode from the App Store.
2. Open Xcode once and accept the license / install additional components.
3. Select full Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

4. If Xcode asks for license agreement:

```bash
sudo xcodebuild -license accept
```

## Simulator install/run

After full Xcode is selected:

```bash
cd <repo root>
xcodebuild -project DamSet.xcodeproj -scheme DamSet -showdestinations
xcodebuild -project DamSet.xcodeproj -scheme DamSet -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Then open `DamSet.xcodeproj` in Xcode, pick an iPhone simulator, and press Run.

## Real iPhone install/run

Prerequisites:

- iPhone connected by USB or visible to Xcode over Wi-Fi.
- iPhone is unlocked.
- “Trust This Computer” accepted on the iPhone.
- Developer Mode enabled on iPhone.
- Xcode Signing & Capabilities has a valid Team selected.

Device checks:

```bash
xcrun xctrace list devices
xcrun devicectl list devices
```

Build/install through Xcode:

1. Open `DamSet.xcodeproj`.
2. Select target `DamSet`.
3. Signing & Capabilities → Team → choose ST/HSUNEH Apple team.
4. Select the connected iPhone as destination.
5. Press Run.

### Real-device attempt 2026-07-03 — blocked, deferred

Connected iPhone 12 mini (`iPhone12,1`). Three stacked blockers found, so
on-device QA was deferred (simulator QA in `docs/qa-automation.md` stands as
the current verification):

1. **Device iOS 26.5 > Xcode 26.3 (max iOS SDK 26.2).** The installed Xcode
   ships no device-support/DDI for iOS 26.5, so deploying to this device is
   very likely refused. Resolving this needs Xcode 26.5+, which needs
   macOS 26.2+ (this Mac is Sequoia 15.7).
2. **Free/personal Apple team cannot create App Groups.** The app↔Live
   Activity extension share state via `group.com.hsuneh.damset`; signing the
   full app with a personal team fails on that entitlement. A paid Apple
   Developer Program membership — or a stripped app-only build (drop the
   extension + App Group, fall back to app-local storage) — is required.
3. **Developer Mode was disabled** on the device (Settings → Privacy &
   Security → Developer Mode → on → reboot). User-only manual step.

The one remaining device-only gap is the **foreground audio cue** (spoken
3-2-1 + horn + haptics over ducked music, `playbackStateAfterCue`), which is
in-app (`InAppRestCuePlayer`) and needs no extension/App Group — so a
stripped app-only build could verify it once the iOS/Xcode version gap is
closed.

Note: `Xcode 26.3` was signed into with Apple ID `iamsuntae@gmail.com`
(Personal Team) for this attempt.

**Update 2026-07-03 (evening): blocker 1 is resolved.** macOS 26.5.2 +
Xcode 26.6 (iOS 26.5 SDK) now match the device's iOS 26.5, and the full
toolchain re-test passed (SwiftPM gate, smoke run, simulator
build/install/launch). Still open for the next on-device session:

- Blocker 2 — build the stripped app-only variant (drop the Live Activity
  extension + App Group) so a free personal team can sign it.
- Blocker 3 — enable Developer Mode on the iPhone and connect it
  (`devicectl` listed it as unavailable/disconnected during this session).

**Update 2026-07-08: on-device install and launch SUCCEEDED — all install
blockers resolved.** What it took, in order:

1. Developer Mode: the Settings toggle only appears after the host pokes the
   device's development channel (`xcrun devicectl device info processes ...`
   is enough; it fails with "Developer Mode disabled" but surfaces the
   toggle). Enable → reboot.
2. First DDI mount additionally requires the phone to be **unlocked**
   (error 12040 until then). State is visible via
   `xcrun devicectl list devices` ("no DDI" annotation disappears).
3. Free-team signing: the **extension does not need the App Group** — the
   Live Activity renders from ActivityKit content state and the intents run
   in the app process, while the stores fall back to app-local containers.
   So instead of stripping the extension, only the App Group entitlements
   were removed (project.yml, 2026-07-08) and the full app + Live Activity
   signs fine with the personal team (`DEVELOPMENT_TEAM: BL626GZ9S8`,
   selected once in Xcode's Signing & Capabilities to mint the identity).
4. Deploy loop (headless):

```bash
xcodebuild -project DamSet.xcodeproj -scheme DamSet \
  -destination 'platform=iOS,id=<udid>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <udid> \
  ~/Library/Developer/Xcode/DerivedData/DamSet-*/Build/Products/Debug-iphoneos/DamSet.app
xcrun devicectl device process launch --device <udid> com.hsuneh.damset
```

5. First launch is blocked until the user trusts the developer profile on
   the phone (Settings → General → VPN & Device Management), and remote
   launch fails with "Locked" while the phone is locked.

Free-team caveats: profiles expire after 7 days (redeploy to refresh) and
history lives in the app-local container (no App Group).

### App Group signing note

The app and the Live Activity extension shared state through the
`group.com.hsuneh.damset` App Group until 2026-07-08, when the entitlements
were removed so a free personal team can sign both targets (see above — the
stores in `WorkoutSessionSync` fall back to app-local containers, and the
Live Activity flow tolerates that because `LiveActivityIntent` runs in the
app process). If a paid team arrives, restore the `entitlements:` blocks on
both targets in `project.yml` (they're in git history; search
`application-groups`) and regenerate — `WorkoutSessionSync.appGroupId` is
still `group.com.hsuneh.damset`.

## First QA after install

1. Launch DamSet.
2. Pick a default routine; accept the notification permission prompt (rest cues).
3. Verify active workout screen shows exercise, set index, target weight/reps, actual reps `- / +`, weight `±2.5`, and Set Done.
4. Tap `- / +` and verify actual reps change.
5. Tap Set Done and verify the rest countdown ticks down and a Live Activity appears (Lock Screen + Dynamic Island).
6. Lock the iPhone: verify the Live Activity shows the rest countdown and resume time; after rest ends, `- / +` and Done should act on the next set.
7. With music playing, verify the rest-end cue per README "Rest cue and iOS audio behavior" and record observed results there.
8. Finish all sets and verify the workout appears under History with per-set records and totals.

## Notes

- Gotcha (hit 2026-07-03): if `xcrun simctl runtime list` shows a duplicate
  runtime disk image ("Unusable — Duplicate of <uuid>"), do **not**
  `simctl runtime delete` the duplicate record — both records share one
  underlying OTA asset, and deleting either removes the asset for both
  (the surviving record then silently unregisters). Recover by re-running
  `xcodebuild -downloadPlatform iOS`.
- `DamSet.xcodeproj` was generated from `project.yml` using XcodeGen.
- XcodeGen is installed locally at `~/.local/bin/xcodegen` (release binary; Homebrew unavailable on this machine).
- Regenerate after editing `project.yml`:

```bash
~/.local/bin/xcodegen generate
```

- Current local non-Xcode gate remains:

```bash
swift build
swift test
swift run DamSetCoreSmoke
ruby -e 'require "yaml"; YAML.load_file("seed.yaml"); puts "seed yaml ok"'
git diff --check
```
