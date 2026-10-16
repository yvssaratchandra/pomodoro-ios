# Pomodoro for iPhone

A native SwiftUI focus timer for iOS 17 and later. Track daily work against an hours-and-minutes goal, organize projects, review completed and interrupted sessions, and export or restore your data.

## Build without owning a Mac

The repository includes `.github/workflows/ios.yml`. GitHub Actions builds and tests on a hosted `macos-26` machine using its default Xcode. No signing secrets or Apple account are needed for this workflow.

1. Create a GitHub repository and push this project to it. If your downloaded folder is not already a Git checkout, run `git init`, add and commit the files, then follow GitHub's instructions for adding your repository remote and pushing.
2. Open the repository's **Actions** tab, then **iOS build and tests**. Pushes and pull requests run it automatically; **Run workflow** also starts it manually.
3. Check the job result. The workflow tests the portable core, runs app/unit/UI tests on an iPhone simulator, and compiles an unsigned Release build for iOS.
4. Download **Pomodoro-IPA** for the unsigned device `Pomodoro.ipa`, **Pomodoro-Native-IPA** for the separate app with its widget extension, **Pomodoro-Simulator** for the container-compatible simulator `.app`, or **build-diagnostics** for logs and the Xcode `.xcresult` test report. The native build has its own **native-build-diagnostics** artifact. Diagnostics are uploaded even when a step fails.

To use your iPhone without a Mac, extract the downloaded **Pomodoro-IPA** artifact ZIP to get `Pomodoro.ipa`. Import it using the **+** button in your configured LiveContainer, or use Sideloadly on your computer to sign and install it. The IPA contains the Release build for physical iOS devices in `Payload/Pomodoro.app`; CI does not sign it or require signing secrets. LiveContainer compatibility, including notifications and file import/export, still needs testing on your device. The simulator artifact cannot run on an iPhone.

TestFlight distribution requires Apple Developer Program membership and an additional signed distribution workflow. This project does not publish releases or upload to TestFlight automatically. GitHub account limits and macOS Actions usage charges may apply; check your repository's Actions billing settings.

The hosted runner and installed SDK versions are recorded in `toolchain.log`. The simulator selector chooses an available iPhone from the newest installed iOS runtime, avoiding dependence on a particular device name.

## Native app and widget extension

The **PomodoroNative** scheme builds a separate app with an embedded **PomodoroWidgets** extension. It shares the app's screens and core logic with **Pomodoro**, while using a separate bundle identifier and private data store. Move data between installations with export/restore. The existing **Pomodoro** scheme and **Pomodoro-IPA** artifact remain available for LiveContainer.

The extension currently provides a small/medium widget that opens the app. Configurable quick start, shared timer data, and Live Activity presentation are still being implemented. The native target declares Live Activity support, but this build structure alone does not provide a Lock Screen timer.

CI builds the native app and extension for Simulator and physical iOS devices in a separate job and packages `Pomodoro-Native.ipa`. These are unsigned build checks. Installation must preserve the extension and provision the same App Group for both targets before widget data sharing can be verified. [Apple widget extensions](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension), [App Groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)

Native signing identifiers are build settings, so they can be supplied through `xcodebuild` or an external `.xcconfig` without editing the generator:

| Setting | Default |
| --- | --- |
| `POMODORO_NATIVE_BUNDLE_ID` | `com.example.Pomodoro.Native` |
| `POMODORO_WIDGET_BUNDLE_ID` | `$(POMODORO_NATIVE_BUNDLE_ID).Widgets` |
| `POMODORO_APP_GROUP` | `group.$(POMODORO_NATIVE_BUNDLE_ID)` |

Both native targets use the same App Group entitlement and expose its resolved value as `PomodoroAppGroup` in their Info.plist. Select a signing team for both targets and supply matching provisioned identifiers. These settings do not alter the container-compatible app's bundle identifier or move its database into a shared container.

For an unsigned native build:

```sh
xcodebuild build \
  -project Pomodoro.xcodeproj -scheme PomodoroNative \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/NativeRelease \
  CODE_SIGNING_ALLOWED=NO
```

## Compile and run on a Mac

### Xcode interface

1. Install the current stable **full Xcode** from the Mac App Store or Apple Developer downloads on a compatible Mac. Xcode 15 or later is required; current Xcode is recommended for current native iOS styling. Command Line Tools alone do not include the iOS SDK or simulator.
2. Launch Xcode once, accept its license, and let it install components. In **Xcode > Settings > Components** (called **Platforms** in some versions), install an iOS simulator runtime.
3. Clone or download this repository and open **Pomodoro.xcodeproj**. No CocoaPods, package download, or project-generation step is required.
4. Select the shared **Pomodoro** scheme and an **iPhone simulator** in the destination picker.
5. Choose **Product > Run** (`Command-R`) to build and launch. Choose **Product > Test** (`Command-U`) to run unit, persistence, and UI tests.

### Terminal

From the repository root, point the developer tools at full Xcode (adjust its path if needed):

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -version
```

Build for Simulator:

```sh
xcodebuild build \
  -project Pomodoro.xcodeproj -scheme Pomodoro \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Select an installed simulator, boot it if needed, and run all tests (requires Python 3 for the selection helper):

```sh
SIMULATOR_ID=$(python3 Scripts/select_simulator.py)
xcrun simctl boot "$SIMULATOR_ID" || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild test \
  -project Pomodoro.xcodeproj -scheme Pomodoro \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/LocalTests.xcresult \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

Choose a fresh `-resultBundlePath` for subsequent runs; Xcode does not overwrite an existing result bundle. Without Python, use `xcrun simctl list devices available` and substitute an iPhone's UDID directly in the destination.

Install and launch the built simulator app:

```sh
open -a Simulator
xcrun simctl install "$SIMULATOR_ID" build/DerivedData/Build/Products/Debug-iphonesimulator/Pomodoro.app
xcrun simctl launch "$SIMULATOR_ID" com.example.Pomodoro
```

Check a Release build for physical iOS devices without signing:

```sh
xcodebuild build \
  -project Pomodoro.xcodeproj -scheme Pomodoro \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath build/Release \
  CODE_SIGNING_ALLOWED=NO
```

### Run on your own iPhone

1. Open the project in Xcode and sign in under **Xcode > Settings > Accounts**.
2. Select the **Pomodoro** app target, then **Signing & Capabilities**. Enable **Automatically manage signing**, choose your development team, and change `com.example.Pomodoro` to a unique bundle identifier you control.
3. Connect and trust the iPhone, enable Developer Mode if prompted, and select it as the run destination.
4. Press `Command-R`. Do not pass `CODE_SIGNING_ALLOWED=NO` for a device installation. A Personal Team can be used where Apple permits free development provisioning; its limitations differ from paid distribution membership.

## Behavior

- Four tabs: **Focus**, **Stats**, **Projects**, **Settings**. Native system controls support light/dark mode, Dynamic Type, and VoiceOver labels. Dark mode uses true-black screen, card, list, and navigation backgrounds, including when following the system appearance.
- Daily goal: initially 4 hours, configurable from 1 minute to 24 hours. Only elapsed focus time counts.
- Focus duration: 10–60 minutes. Project defaults begin at 25-minute focus, 5-minute short break, and 15-minute long break; breaks accept 1–60 minutes.
- Focus opens with a large countdown and progress ring, followed by session controls, today's goal, and project metrics. Accessibility text sizes use a progress bar to leave room for larger numbers.
- Each project remembers the last focus duration saved with **Done** in the duration sheet, including across tabs and app restarts. **Cancel** discards picker changes. Editing a project's focus default clears its remembered duration; renaming and status changes preserve it. During a timer, duration selection applies only to the next session. Backups preserve these preferences and older backups continue to load using project defaults.
- One timer at a time, with no pause. Ending focus offers **End and Save Work** to save an interrupted session, **Discard Session** to remove all elapsed work from that session, or **Keep Focusing** to continue. Discarding does not advance the break cycle. Breaks have visible countdowns and never count as work. Every phase starts manually.
- A long break is offered every four completed sessions by default; configure 1–12 in Settings. Completion counts across projects, including across days. Changing the interval while idle resets cycle progress. Skipping a long break still begins a new cycle.
- Switching the selected project updates its stats and the next-session configuration. The running timer retains its original project. Starting focus while a break is offered skips that pending break.
- Today's project total and seven-day daily average include active focus time. Averages include today plus the preceding six calendar days, including zeros. Work crossing midnight is divided between local days. Changing time zones recalculates day grouping in the current device time zone.
- Stats shows today's completed and interrupted focus sessions, plus any active focus. Switch to **All history** to access older sessions. Swipe left or long-press a saved session to delete it after confirmation; VoiceOver also exposes a Delete Session action. Deletion removes the entire session from all statistics, including both days of a cross-midnight session, and persists across relaunches. It does not change the running timer, pending break, or break cycle progress. For cross-midnight sessions the Today view shows the full duration and the portion counted today.
- Suspended/completed projects retain history and can be reopened. Merge moves all source history into the destination, preserves destination settings/status, and removes the source. End timers involving either project before merging.
- Background/relaunch recovery uses saved start/deadline timestamps. Work stops accumulating at the deadline even if the app is closed, and no next phase begins automatically. Notifications use the iPhone’s default notification sound when sound is enabled; no custom audio is bundled. Notifications depend on iOS permissions, Focus mode, and device settings. Manually changing the device clock can affect timestamp-based timers.
- Backups are versioned JSON with projects, sessions, settings, pending break, and cycle progress. Dates use Foundation reference-date seconds (since January 1, 2001 UTC), preserving fractional seconds. Export/restore requires an idle timer. Restore validates the whole file before replacing data. Keep exported files private; they contain project names and work history. Import size limit: 50 MB.

## Structure and tests

- `Pomodoro/Core`: Foundation-only models, timer transitions, calendar statistics, and backup validation.
- `Pomodoro/App`: app lifecycle, notification scheduling, and an observable store. SwiftData persists one versioned document so a session transition, project merge, or restore uses a single atomic save. All edits are validated before saving; failures retain the previous state.
- `Pomodoro/Views`: native SwiftUI screens and forms.
- `Tests/Core`, `Tests/App`, `Tests/UI`: timer/statistics/backup tests, SwiftData restore tests, and a simulator UI smoke test. UI tests use a fresh in-memory store.
- `PomodoroWidgets`: the native widget extension. It compiles only its own views and the explicitly shared Foundation models; it cannot access the app's SwiftData store.
- `Config`: native app and extension entitlements, using overridable App Group settings.
- `Scripts/generate_project.py`: the source of truth for target membership, build settings, and shared schemes. Run it after adding/removing Swift files. Keep signing overrides in an external `.xcconfig` or command-line settings because regeneration overwrites project edits.
- `Tests/Build`: project structure, entitlement, source membership, scheme, and generation checks, run with `python3 -m unittest discover -s Tests/Build -v`.

Run portable tests on any supported Swift 5.9+ toolchain:

```sh
swift test
```

The Swift package contains only the Foundation core, so Linux can run these logic tests when Swift is installed. It cannot compile SwiftUI/SwiftData or run iOS Simulator.

Before distribution, also check on simulator/device: largest accessibility text sizes, VoiceOver navigation, light/dark mode, landscape, denied notifications, background/lock/relaunch recovery, file export/restore, and midnight transitions. Test an iOS 17 simulator when available as well as the current runtime.

## Validation status

The current portable suite has 38 core XCTest cases, verified with Swift 6.0.3 on Linux. Project checks cover native/container separation, extension embedding, signing configuration, entry points, shared-scheme XML, and deterministic generation. Swift syntax parsing and these structural checks do not type-check SwiftUI, SwiftData, or WidgetKit against an iOS SDK.

The checked-in workflow provides the macOS build/test path for both schemes; a successful run for the current commit is required before treating iOS builds as verified. The container scheme also runs persistence and UI tests. Native device signing, App Group access, and widget installation remain unverified until checked on a physical iPhone.
