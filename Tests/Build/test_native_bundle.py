import plistlib
from pathlib import Path
import runpy
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[2]
bundle_tools = runpy.run_path(str(ROOT / "Scripts/verify_native_bundle.py"))
verify = bundle_tools["verify"]
prepare = bundle_tools["prepare"]


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
        verify(self.app, lambda bundle: {"com.apple.security.application-groups": ["group.org.example.Focus"]})

    def test_missing_or_mismatched_signed_groups_are_rejected(self):
        self.write()
        for groups in ([], ["group.other"], ["group.org.example.Focus", "group.other"]):
            with self.subTest(groups=groups):
                with self.assertRaises(ValueError):
                    verify(self.app, lambda bundle: {"com.apple.security.application-groups": groups})
        with self.assertRaises(ValueError):
            verify(self.app, lambda bundle: {"com.apple.security.application-groups":
                   ["group.org.example.Focus"] if bundle == self.app else []})

    def test_packaging_signs_extension_before_app_and_verifies_permissions(self):
        self.write()
        signed = []
        checked = []

        def codesign(arguments, **kwargs):
            bundle = Path(arguments[-1])
            self.assertEqual(arguments[0], "codesign")
            if "--sign" in arguments:
                self.assertEqual(arguments[arguments.index("--sign") + 1], "-")
                entitlement_path = Path(arguments[arguments.index("--entitlements") + 1])
                with entitlement_path.open("rb") as file:
                    self.assertEqual(plistlib.load(file), {"com.apple.security.application-groups":
                                                        ["group.org.example.Focus"]})
                signed.append(bundle)
            elif "--display" in arguments:
                self.assertIn(bundle, signed)
                return SimpleNamespace(stdout=plistlib.dumps({"com.apple.security.application-groups":
                                                            ["group.org.example.Focus"]}))
            elif "--verify" in arguments:
                checked.append(bundle)
            else:
                self.fail("Unexpected signing operation")
            return SimpleNamespace(stdout=b"")

        with patch("subprocess.run", side_effect=codesign):
            prepare(self.app)
        self.assertEqual(signed, [self.extension, self.app])
        self.assertEqual(checked, [self.extension, self.app])

    def test_missing_custom_plist_key_or_unexpanded_group_is_rejected(self):
        for group in (None, "", "$(POMODORO_APP_GROUP)", "invalid-group"):
            with self.subTest(group=group):
                if group is None:
                    self.host.pop("PomodoroAppGroup", None)
                else:
                    self.host["PomodoroAppGroup"] = group
                self.write()
                with self.assertRaises(ValueError):
                    verify(self.app, lambda bundle: {"com.apple.security.application-groups": ["group.org.example.Focus"]})

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
                    verify(self.app, lambda bundle: {"com.apple.security.application-groups": ["group.org.example.Focus"]})

    def test_missing_extension_and_nonboolean_live_activity_support_are_rejected(self):
        self.write()
        (self.extension / "Info.plist").unlink()
        with self.assertRaises(FileNotFoundError):
            verify(self.app, lambda bundle: {"com.apple.security.application-groups": ["group.org.example.Focus"]})
        self.host["NSSupportsLiveActivities"] = "YES"
        self.write()
        with self.assertRaises(ValueError):
            verify(self.app, lambda bundle: {"com.apple.security.application-groups": ["group.org.example.Focus"]})


if __name__ == "__main__":
    unittest.main()
