# Pomodoro for iPhone

A native SwiftUI focus timer for iOS 17 and later. Add a session note, save distractions for later, organize projects, and review daily, weekly, and monthly progress. Export or restore your history and settings.

## Build without owning a Mac

The repository includes `.github/workflows/ios.yml`. GitHub Actions builds and tests on a hosted `macos-26` machine using its default Xcode. No signing secrets or Apple account are needed for this workflow.

1. Create a GitHub repository and push this project to it. If your downloaded folder is not already a Git checkout, run `git init`, add and commit the files, then follow GitHub's instructions for adding your repository remote and pushing.
2. Open the repository's **Actions** tab, then **iOS build and tests**. Pushes and pull requests run it automatically; **Run workflow** also starts it manually.
3. Check the job result. The workflow tests the portable core, runs app/unit/UI tests on an iPhone simulator, and compiles an unsigned Release build for iOS.
4. Download **Pomodoro-IPA** for the unsigned device `Pomodoro.ipa`, **Pomodoro-Native-IPA** for the separate app with its widget extension, **Pomodoro-Simulator** for the container-compatible simulator `.app`, or **build-diagnostics** for logs and the Xcode `.xcresult` test report. The native build has its own **native-build-diagnostics** artifact. Diagnostics are uploaded even when a step fails.

To use your iPhone without a Mac, extract the downloaded **Pomodoro-IPA** artifact ZIP to get `Pomodoro.ipa`. Import it using the **+** button in your configured LiveContainer, or use Sideloadly on your computer to sign and install it. The IPA contains the Release build for physical iOS devices in `Payload/Pomodoro.app`; CI does not sign it or require signing secrets. LiveContainer compatibility, including notifications and file import/export, still needs testing on your device. The simulator artifact cannot run on an iPhone.

TestFlight distribution requires Apple Developer Program membership and an additional signed distribution workflow. This project does not publish releases or upload to TestFlight automatically. GitHub account limits and macOS Actions usage charges may apply; check your repository's Actions billing settings.

The hosted runner and installed SDK versions are recorded in `toolchain.log`. The simulator selector chooses an available iPhone from the newest installed iOS runtime, avoiding dependence on a particular device name.

## Build with Codemagic

The root `codemagic.yaml` provides a manual **LiveContainer IPA** workflow on a Mac M2 runner. Connect this repository in Codemagic, select `main`, click **Check for configuration files**, then start **LiveContainer IPA**. Download `Pomodoro.ipa` from the build artifacts and import it into LiveContainer. This unsigned build does not require Apple signing credentials.

The **LiveContainer IPA** workflow runs the project checks and portable core tests, builds the container-compatible Release app, and saves its IPA and build logs. It omits simulator tests and the native widget variant to reduce build time. No push, pull request, or scheduled triggers are configured; start a build manually when needed.

For a release check, select **LiveContainer verification** instead. It runs the same checks plus the app and UI tests on an iPhone simulator, then builds the IPA. It publishes `TestResults.zip` containing the Xcode `.xcresult` report and screenshots, including when simulator tests fail. This workflow has a 45-minute limit and remains manual. Run only this workflow when you need both verification and an IPA; a separate quick build is unnecessary. A passing build does not verify notification delivery or file import/export inside LiveContainer on your phone.

## Native app and widget extension

The **PomodoroNative** scheme builds a separate app with an embedded **PomodoroWidgets** extension. It shares the app's screens and core logic with **Pomodoro**, while using a separate bundle identifier and private data store. Move data between installations with export/restore. The existing **Pomodoro** scheme and **Pomodoro-IPA** artifact remain available for LiveContainer.

The extension provides configurable small/medium quick-start widgets and a Live Activity with Lock Screen and Dynamic Island countdowns. The medium widget also shows saved focus time for the current local day and a compact **Thought** link. The Lock Screen card and expanded Island include capture links; these open the app directly into thought capture. Select an active project in the widget configuration. Its link starts that project immediately when idle, or opens the existing timer when occupied. Widget data is a small, read-only snapshot; the database stays private to the app. Live Activity project names and session notes are hidden by default and have separate privacy toggles in Settings. Signed installation and App Group access still require the physical checks in [COMPATIBILITY.md](COMPATIBILITY.md).

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

Codemagic also has a manual **Native IPA** workflow. It checks the project and portable core, builds the native Release app with its embedded extension, validates the bundle, and produces `Pomodoro-Native.ipa`. Select this workflow for direct installation through SideStore and retain the extension when installing. The IPA is unsigned; signing and shared App Group access still need verification on the phone. No automatic native Codemagic trigger is configured.

## Quick-start shortcuts

Open **Focus > Settings (gear) > Widgets & shortcuts**, or **Create shortcut** in an active project's menu. Choose the project, copy its shortcut URL, and create a shortcut using **Open URLs**. Add it to the Home Screen or Apple's Shortcuts widget. Opening the link starts focus immediately with the project's current remembered duration. If a focus or break timer is running, the link opens that timer instead.

For LiveContainer, open **Connection settings**, keep **Use LiveContainer** enabled, and save the URL copied from Pomodoro's **Add to Home Screen > Copy Launch URL** menu in LiveContainer. Set this connection once; later shortcuts reuse it. Invalid edits leave the saved connection intact. The setup preserves the selected LiveContainer instance and container. The copied launch URL stays in device preferences and is excluded from portable backups. If Pomodoro is installed directly, turn **Use LiveContainer** off. The native build uses direct links.

Check a shortcut with Pomodoro both closed and already open. Forwarding depends on the installed LiveContainer version. If it only launches the app, **Troubleshooting > Copy app-launch link** provides a fallback; open it and tap **Start Focus** in Pomodoro. The current host URL format is based on [LiveContainer's launch handler](https://github.com/LiveContainer/LiveContainer/blob/main/LiveContainerSwiftUI/Views/AppList/LCAppListView.swift); the physical-device compatibility check is still pending.

The **Add thought** section in Widgets & shortcuts provides a separate capture link, even without any projects. Create an **Open URLs** shortcut and add it to the Home Screen with a compose icon and the name **Add thought**. The link opens capture for the currently running focus session; while idle or on break it opens an unassigned thought with a project picker. Repeated links preserve an already open capture draft. Links wait for another editor to close instead of dismissing unsaved work.

The container-compatible app handles `pomodoro://focus?project=UUID&action=start`, `pomodoro://timer`, `pomodoro://projects/new`, and `pomodoro://thoughts/new`. A capture link can optionally include `?session=UUID` to attach to that focus session; unavailable session IDs open unassigned capture rather than attaching to a different running session. The `pomodoro://plan/next?project=UUID` link opens that project’s next-session plan without starting or changing a timer. The native app uses the same routes with `pomodoro-native`. Links use the current project state, so an unavailable project produces a message instead of starting another project. Ordinary app launch never starts a session automatically.

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

- The three tabs are **Focus**, **Thoughts**, and **Stats**. Open Settings with the gear on Focus, and Projects through **More > Manage projects**.
- **Focus** shows the project, duration, and Start button. **More > Plan this session** adds an optional bullet list of tasks (280 characters total). The ready and running screens show a subdued **Session plan · N tasks** row; tap it to open the plan. Drafts survive navigation between screens and projects until used. Create a project by entering its name. Project and duration stay read-only while a timer runs; each project remembers its selected duration.
- Session plans show saved tasks above a fixed **Add a task…** composer, matching Add a thought. The upward arrow saves each addition immediately; multiline input adds separate tasks. Tap a task to edit it or swipe to delete it. **Done** closes the screen and offers **Keep editing** or **Discard draft** for unsaved input. The same editor works before focus, during focus, and for saved sessions.
- During focus, the half-filled circle beside Settings enables **Dim Focus**. Both toolbar symbols use the same size and touch target. The screen becomes black with a thin purple progress bar and a **+** for session thoughts. Tap the background to reveal Focus temporarily; it dims again after five idle seconds. Editors, menus, other tabs, and accessibility services suspend automatic return. Dim Focus starts off for every new session and after relaunch, releases screen-awake behavior outside the dim surface, and ends at the session deadline. It does not change system brightness. Breaks use a muted sage accent in light and dark appearance.
- Focus accepts 10–60 minutes; breaks accept 1–60 minutes. Defaults are 25/5/15 minutes. Every phase starts manually. Ending early offers **Save Session**, **Discard Session**, or **Keep Focusing**. Discarded time does not count, and captured thoughts remain saved.
- Completed focus sessions advance the break cycle across projects and days. A long break is offered every four completions by default. Timer settings allow 1–12; changing the interval while idle resets the cycle. Background recovery uses the stored deadline without automatically starting another phase.
- **Stats** offers Today, Week, Month, and All, with project filters. Charts, comparisons, and recent sessions follow that selection; one **Details** screen holds daily breakdowns, counts, and project totals. Today shows the daily goal alongside the total; tap its label to edit the schedule. **Saved focus time** counts completed and early-saved sessions only. A small **Session in progress** label appears for a matching running focus session, which contributes after it is saved. Current weeks and months compare matching calendar days in the previous period; historical periods compare in full. Summary durations use whole minutes (or **<1 min**), while calculations and backups retain exact seconds. Cross-midnight work is split by local day; session counts use the start day.
- Swipe a session or thought to delete it, then use **Undo** above the tab bar. Consecutive deletions share one batch, restored atomically. Undo lasts 10 seconds, or 30 seconds with VoiceOver, and does not survive process termination. Bulk thought deletion asks for confirmation first.
- **Thoughts** opens to unfinished items across all projects. It supports standalone entries, search, toolbar status/project filters, and bulk selection under More. **Add a thought** during focus opens **Session thoughts**, showing every thought captured in that session, including completed items. A compact input stays beneath the saved list. The upward arrow explicitly adds a thought, clears the input, and keeps the keyboard ready for another. It is disabled for blank input. **Done** closes an empty input; with unsaved text it offers **Keep editing** or **Discard draft** and never saves it automatically. Standalone capture shows entries added during that visit. Checking an item marks it done and removes it from Open; find it in Done or All, where it is crossed out. Uncheck it to reopen it. Reset clears search and filters back to Open / All projects. Session deletion/discard never removes its thoughts.
- **This session** describes the current work. **Next time** remembers where to resume a project, shown as one compact reminder on Focus. Historical next-step edits replace the project's reminder only when explicitly selected. Deleting the originating session leaves the reminder intact.
- **Projects** separates active, on-hold, and completed projects. All retain their history. Empty projects can be deleted after confirmation; projects with content can be put on hold or merged. Merge transfers history and thoughts while preserving the destination's settings and reminder.
- **Goals** opens with the daily focus schedule. Project weekly targets and consistency are under More goals. Daily schedules support Every day, Weekdays/Weekend, and Custom; zero means rest. Daily edits begin today; weekly edits begin this week. Previous periods remain unchanged, and any previously scheduled future target remains separately editable.
- **Consistency**, available from Stats, counts days with at least 10 minutes of focus, from saved sessions, including early-ended sessions. Running sessions do not contribute. Set a weekly target of 1–7 days and review the previous eight weeks without streak penalties.
- **Sounds & haptics** offers separate focus/break sounds and explicit previews. Changes update the running timer's pending alert without moving its deadline. The native app supports bundled tones; LiveContainer currently offers System Default and Silent. Audio follows system alert volume, Silent mode, Focus, and notification permissions. Already-delivered sounds cannot be recalled.
- Light and dark appearance, Dynamic Type, and VoiceOver are supported. Dark screen backgrounds remain black. Accessibility text sizes replace the ring with a progress bar and allow scrolling.
- Backups contain projects, sessions, notes, thoughts and check states, dated goals, preferences, pending break, and cycle progress. Schema 8 accepts unassigned thoughts and migrates versions 1–7. Export/restore requires an idle timer; restore validates the whole file before replacing data. The import limit is 50 MB.

## Structure and tests

- `Pomodoro/Core`: Foundation-only models, timer transitions, calendar statistics, and backup validation.
- `Pomodoro/App`: app lifecycle, notification scheduling, and an observable store. SwiftData persists one versioned document so a session transition, project merge, or restore uses a single atomic save. All edits are validated before saving; failures retain the previous state.
- `Pomodoro/Views`: native SwiftUI screens and forms.
- `Tests/Core`, `Tests/App`, `Tests/UI`: timer/statistics/backup tests, SwiftData restore tests, and simulator UI flows with screenshot coverage. UI tests use an isolated store; launch-recovery tests use a unique temporary disk store.
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

The current portable suite has 97 core XCTest cases, verified with Swift 6.0.3 on Linux. Project checks cover native/container separation, extension embedding, signing configuration, URL scheme registration, entry points, shared-scheme XML, and deterministic generation. Swift syntax parsing and these structural checks do not type-check SwiftUI, SwiftData, or WidgetKit against an iOS SDK.

The checked-in workflow provides the macOS build/test path for both schemes; a successful run for the current commit is required before treating iOS builds as verified. The container scheme also runs persistence and UI tests. Native device signing, App Group access, and widget installation remain unverified until checked on a physical iPhone.
