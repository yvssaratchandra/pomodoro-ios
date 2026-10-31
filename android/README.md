# Pomodoro for Android

Native Kotlin and Jetpack Compose application. The iPhone and Android applications have separate stores and share the portable JSON backup format.

## Local build

Install JDK 17 and Android SDK platform 36. Set `ANDROID_HOME` or create an untracked `local.properties` containing `sdk.dir=/path/to/Android/Sdk`.

```sh
./gradlew :core:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug
```

Debug installations use `com.jamesblack.pomodoro.debug`; Play releases use `com.jamesblack.pomodoro`. Debug and release data are separate. Emulator checks do not prove notification delivery on a physical device.

## Release bundle

Create and retain an upload key outside this repository. Supply the following environment variables through your local credential manager or build environment:

- `POMODORO_UPLOAD_STORE`: absolute keystore path
- `POMODORO_UPLOAD_STORE_PASSWORD`
- `POMODORO_UPLOAD_KEY_ALIAS`
- `POMODORO_UPLOAD_KEY_PASSWORD`

Run `./gradlew :app:bundleRelease`. Without these inputs, a release bundle is unsigned and cannot be uploaded to Play. Never commit keys or passwords. Increment `versionCode` before each new Play upload; keep the application ID unchanged.

## Google Play internal testing

1. Register and verify a personal Play Console account, including physical-device verification through the Play Console app.
2. Create Pomodoro as a free app, upload the signed AAB to **Testing → Internal testing**, and enroll in Play App Signing. Complete the requirements shown for your account and track.
3. Add the Google account used by the intended phone as a tester. Open the test opt-in link using that account, join, and install from Google Play.
4. Verify completion while foregrounded, backgrounded and locked, permission denial, Do Not Disturb, battery-saving behavior, reboot recovery, and update preservation on the actual phone.

Use the internal testing track, rather than internal app sharing or sideloading. A work-device administrator can still restrict installation or notifications. A build artifact alone does not verify Play acceptance or device behavior.

Internal testing does not require a public launch. New personal accounts seeking production access have additional closed-testing requirements. Check the current [Play testing guidance](https://support.google.com/googleplay/android-developer/answer/14151465) before expanding distribution.

## Data handling

App data stays in private device storage. The application has no account, advertising, analytics or backend. Manual JSON export can place a backup in a storage provider chosen by the user; that provider controls any subsequent upload. Import replaces local app data after confirmation. Automatic backup and device transfer of app storage are disabled. Android notification content follows the lock-screen privacy settings and the phone's notification controls.
