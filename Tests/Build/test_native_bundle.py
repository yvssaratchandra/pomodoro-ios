import plistlib
from pathlib import Path
import runpy
from tempfile import TemporaryDirectory
import unittest


ROOT = Path(__file__).resolve().parents[2]
verify = runpy.run_path(str(ROOT / "Scripts/verify_native_bundle.py"))["verify"]


class NativeBundleTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name) / "PomodoroNative.app"
        self.extension = self.app / "PlugIns/PomodoroWidgets.appex"
        self.extension.mkdir(parents=True)
        self.host = {"CFBundleIdentifier": "org.example.Focus", "PomodoroAppGroup": "group.org.example.Focus",
                     "NSSupportsLiveActivities": True, "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"}
        self.widget = {"CFBundleIdentifier": "org.example.Focus.Widgets", "PomodoroAppGroup": "group.org.example.Focus",
                       "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"},
                       "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"}

    def write(self):
        for directory, values in ((self.app, self.host), (self.extension, self.widget)):
            with (directory / "Info.plist").open("wb") as file:
                plistlib.dump(values, file)

    def test_valid_bundle_with_overridden_identifiers(self):
        self.write()
        verify(self.app)

    def test_missing_custom_plist_key_or_unexpanded_group_is_rejected(self):
        for group in (None, "", "$(POMODORO_APP_GROUP)", "invalid-group"):
            with self.subTest(group=group):
                if group is None:
                    self.host.pop("PomodoroAppGroup", None)
                else:
                    self.host["PomodoroAppGroup"] = group
                self.write()
                with self.assertRaises(ValueError):
                    verify(self.app)

    def test_wrong_extension_identity_group_or_version_is_rejected(self):
        original = self.widget.copy()
        for key, value in [("CFBundleIdentifier", "org.other.Widgets"),
                           ("PomodoroAppGroup", "group.other"),
                           ("NSExtension", {"NSExtensionPointIdentifier": "com.apple.share-services"}),
                           ("CFBundleShortVersionString", "2.0"), ("CFBundleVersion", "2")]:
            with self.subTest(key=key):
                self.widget = {**original, key: value}
                self.write()
                with self.assertRaises(ValueError):
                    verify(self.app)

    def test_missing_extension_and_nonboolean_live_activity_support_are_rejected(self):
        self.write()
        (self.extension / "Info.plist").unlink()
        with self.assertRaises(FileNotFoundError):
            verify(self.app)
        self.host["NSSupportsLiveActivities"] = "YES"
        self.write()
        with self.assertRaises(ValueError):
            verify(self.app)


if __name__ == "__main__":
    unittest.main()
