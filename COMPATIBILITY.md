# Installation checks

Target phone: iPhone 14 Pro, iOS 18.7.8. The intended container setup is SideStore plus LiveContainer. The installed LiveContainer version has not been recorded yet.

| Check | Status |
| --- | --- |
| Container-compatible simulator compilation | Passed in CI with the feature set |
| Native app and embedded extension, unsigned simulator/device compilation | Passed in unsigned CI builds with configurable widgets and Live Activities; consult the build result for the version being installed |
| Current native integration and UI tests | GitHub workflow covers both variants; manual Codemagic verification covers the container app/unit/UI suite. Consult the exact commit result before installing |
| Native signing, retained extension, and App Group access on phone | Not tested |
| Home Screen widget start with idle/running/expired timer | Not tested on phone |
| Live Activity with Lock Screen and Dynamic Island | Not tested on phone |
| LiveContainer forwarding from closed/open app | Not tested on installed version |
| Default notification sound while locked | Not tested on phone |
| Named custom notification sound in LiveContainer | Not tested; container custom-sound capability stays disabled |

Unsigned artifacts do not verify signing or extension registration. Record the signing method, OS and LiveContainer version when checking the phone. Test both cold and warm shortcut launches, focus and break completion, denied permissions, Silent mode, and background/locked sound delivery. Check that private project/intention text is absent from Live Activity content unless explicitly enabled.

If native signing cannot retain the extension or App Group, use the container-compatible artifact. If LiveContainer does not forward the guest URL, use the app-launch fallback and tap Start Focus. Enable custom notification sounds in the container release only after a named sound is verified on the supported phone/version. Independent in-app features can be used while these physical checks are pending.

## Saved statistics and recovery checks

Automated coverage checks saved-only totals, stable calendar-day comparisons, delayed timer recovery, failed-save retries, and backup restore/reload. Local core tests do not execute SwiftData, notifications, or the iOS interface. The manual **LiveContainer verification** workflow exercises app persistence and UI tests on a simulator; record its result separately from phone checks.

Use a disposable test installation for backup restoration. Export a representative idle snapshot with session notes, next-time reminders, assigned and unassigned thoughts (including a completed item), goals, and settings. Restore it from Files and reopen the app; check that saved content and totals match. Keep your primary history separate from this test.

| Phone check | Expected result | Status |
| --- | --- | --- |
| Focus completion in foreground, background, and while locked | Completion alert follows notification permissions, Silent mode, and Focus settings | Not tested |
| Reopen after focus expires | Exactly one saved session ending at its original deadline, with the expected break offer | Not tested |
| End or discard focus before expiry | No completion alert at the discarded timer's original deadline | Not tested |
| Complete a break | Saved focus total does not increase | Not tested |
| Export and restore through Files, then relaunch | Representative saved content and totals are preserved | Not tested |

Record the iOS version, LiveContainer version, build commit, and results when performing these checks. For audible checks, enable notification sounds and turn off Silent mode and Focus restrictions first. An unsigned build alone cannot establish these results.
