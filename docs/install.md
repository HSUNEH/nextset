# NextSet install guide

## Current state

**Xcode 26.3 (17C529) is installed at `/Applications/Xcode.app`** (downloaded
from developer.apple.com — the App Store's newer Xcode requires macOS 26.2+,
while this Mac runs Sequoia 15.7; Xcode 26.3 is the last release supporting
macOS 15.6+). The global `xcode-select` still points at Command Line Tools on
purpose; prefix commands with `DEVELOPER_DIR` instead:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version   # Xcode 26.3
```

The iOS 26.3.1 simulator runtime is installed (`xcodebuild -downloadPlatform iOS`)
and the app has been built, installed, and QA'd on the iPhone 17 Pro simulator
(see `docs/qa-automation.md`).

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
xcodebuild -project NextSet.xcodeproj -scheme NextSet -showdestinations
xcodebuild -project NextSet.xcodeproj -scheme NextSet -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Then open `NextSet.xcodeproj` in Xcode, pick an iPhone simulator, and press Run.

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

1. Open `NextSet.xcodeproj`.
2. Select target `NextSet`.
3. Signing & Capabilities → Team → choose ST/HSUNEH Apple team.
4. Select the connected iPhone as destination.
5. Press Run.

### App Group signing note

The app and the Live Activity extension share state through the
`group.com.hsuneh.nextset` App Group (both targets carry generated
`.entitlements` files). With automatic signing, Xcode registers the group on
the selected team the first time you build. If the chosen team cannot register
that identifier, change the group id in both entitlement blocks in
`project.yml` **and** in `WorkoutSessionSync.appGroupId`
(`Sources/NextSetCore/LiveActivitySupport.swift`), then regenerate the project.

## First QA after install

1. Launch NextSet.
2. Pick a default routine; accept the notification permission prompt (rest cues).
3. Verify active workout screen shows exercise, set index, target weight/reps, actual reps `- / +`, weight `±2.5`, and Set Done.
4. Tap `- / +` and verify actual reps change.
5. Tap Set Done and verify the rest countdown ticks down and a Live Activity appears (Lock Screen + Dynamic Island).
6. Lock the iPhone: verify the Live Activity shows the rest countdown and resume time; after rest ends, `- / +` and Done should act on the next set.
7. With music playing, verify the rest-end cue per README "Rest cue and iOS audio behavior" and record observed results there.
8. Finish all sets and verify the workout appears under History with per-set records and totals.

## Notes

- `NextSet.xcodeproj` was generated from `project.yml` using XcodeGen.
- XcodeGen is installed locally at `~/.local/bin/xcodegen` (release binary; Homebrew unavailable on this machine).
- Regenerate after editing `project.yml`:

```bash
~/.local/bin/xcodegen generate
```

- Current local non-Xcode gate remains:

```bash
swift build
swift run NextSetCoreSmoke
ruby -e 'require "yaml"; YAML.load_file("seed.yaml"); puts "seed yaml ok"'
git diff --check
```
