# Installation checks

Target phone: iPhone 14 Pro, iOS 18.7.8. The intended container setup is SideStore plus LiveContainer. The installed LiveContainer version has not been recorded yet.

| Check | Status |
| --- | --- |
| Container-compatible simulator compilation | Passed in the initial quick-start CI build |
| Native app and embedded extension, unsigned simulator/device compilation | Passed before configurable widgets and Live Activities; current changes require a new CI run |
| Current native integration and UI tests | Run by the checked-in CI workflow |
| Native signing, retained extension, and App Group access on phone | Not tested |
| Home Screen widget start with idle/running/expired timer | Not tested on phone |
| Live Activity with Lock Screen and Dynamic Island | Not tested on phone |
| LiveContainer forwarding from closed/open app | Not tested on installed version |
| Default notification sound while locked | Not tested on phone |
| Named custom notification sound in LiveContainer | Not tested; container custom-sound capability stays disabled |

Unsigned artifacts do not verify signing or extension registration. Record the signing method, OS and LiveContainer version when checking the phone. Test both cold and warm shortcut launches, focus and break completion, denied permissions, Silent mode, and background/locked sound delivery. Check that private project/intention text is absent from Live Activity content unless explicitly enabled.

If native signing cannot retain the extension or App Group, use the container-compatible artifact. If LiveContainer does not forward the guest URL, use the app-launch fallback and tap Start Focus. Enable custom notification sounds in the container release only after a named sound is verified on the supported phone/version. Independent in-app features can be used while these physical checks are pending.
