import plistlib
from pathlib import Path
import runpy
import wave
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]


class ProjectTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generated = runpy.run_path(str(ROOT / "Scripts/generate_project.py"))
        cls.objects = cls.generated["objects"]
        cls.targets = {item["name"]: item for item in cls.objects.values()
                       if item["isa"] == "PBXNativeTarget"}

    def settings(self, name):
        configs = self.objects[self.targets[name]["buildConfigurationList"]]["buildConfigurations"]
        return [self.objects[identifier]["buildSettings"] for identifier in configs]

    def phases(self, name, kind):
        return [self.objects[identifier] for identifier in self.targets[name]["buildPhases"]
                if self.objects[identifier]["isa"] == kind]

    def sources(self, name):
        return {self.objects[self.objects[identifier]["fileRef"]]["path"]
                for phase in self.phases(name, "PBXSourcesBuildPhase") for identifier in phase["files"]}

    def test_target_products_and_dependencies(self):
        self.assertEqual(set(self.targets), {"Pomodoro", "PomodoroNative", "PomodoroWidgets",
                                            "PomodoroTests", "PomodoroNativeTests", "PomodoroUITests"})
        native = self.targets["PomodoroNative"]
        widget = self.targets["PomodoroWidgets"]
        self.assertEqual(widget["productType"], "com.apple.product-type.app-extension")
        product = self.objects[widget["productReference"]]
        self.assertEqual(product["path"], "PomodoroWidgets.appex")
        self.assertEqual(product["explicitFileType"], "wrapper.app-extension")
        self.assertEqual([self.objects[identifier]["target"] for identifier in native["dependencies"]],
                         [self.generated["uid"]("PomodoroWidgets.target")])
        self.assertFalse(self.targets["Pomodoro"]["dependencies"])

    def test_only_native_app_embeds_widget(self):
        phases = self.phases("PomodoroNative", "PBXCopyFilesBuildPhase")
        self.assertEqual(len(phases), 1)
        self.assertEqual(phases[0]["dstSubfolderSpec"], 13)
        files = phases[0]["files"]
        self.assertEqual(len(files), 1)
        self.assertEqual(self.objects[files[0]]["fileRef"], self.targets["PomodoroWidgets"]["productReference"])
        self.assertIn("RemoveHeadersOnCopy", self.objects[files[0]]["settings"]["ATTRIBUTES"])
        self.assertFalse(self.phases("Pomodoro", "PBXCopyFilesBuildPhase"))

    def test_entry_points_and_extension_source_boundary(self):
        container = self.sources("Pomodoro")
        native = self.sources("PomodoroNative")
        widget = self.sources("PomodoroWidgets")
        self.assertTrue(container.issubset(native))
        self.assertTrue({"Pomodoro/Core/Models.swift", "Pomodoro/Core/ExternalSurfaces.swift"}.issubset(widget))
        shared = {"Pomodoro/Core/Models.swift", "Pomodoro/Core/ExternalSurfaces.swift", "Pomodoro/Core/WidgetSnapshotFile.swift", "Pomodoro/Core/LiveActivityProjection.swift", "Pomodoro/Core/CompletionSound.swift", "Pomodoro/Core/GoalEngine.swift", "Pomodoro/Core/Breadcrumb.swift", "Pomodoro/Core/CapturedThought.swift"}
        self.assertFalse(widget.intersection(container - shared))
        for name, expected in [("Pomodoro", "Pomodoro/App/PomodoroApp.swift"),
                               ("PomodoroNative", "Pomodoro/App/PomodoroApp.swift"),
                               ("PomodoroWidgets", "PomodoroWidgets/PomodoroWidgets.swift")]:
            entry_points = [path for path in self.sources(name) if "@main " in (ROOT / path).read_text()]
            self.assertEqual(entry_points, [expected])

    def test_shared_files_have_distinct_build_memberships(self):
        build_ids = []
        for target in self.targets:
            for phase in self.phases(target, "PBXSourcesBuildPhase"):
                build_ids.extend(phase["files"])
        self.assertEqual(len(build_ids), len(set(build_ids)))

    def test_native_flags_entitlements_and_bundle_ids(self):
        for name in ("PomodoroNative", "PomodoroWidgets"):
            for settings in self.settings(name):
                self.assertEqual(settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"],
                                 ["$(inherited)", "NATIVE_INTEGRATIONS"])
                path = ROOT / settings["CODE_SIGN_ENTITLEMENTS"]
                with path.open("rb") as file:
                    entitlements = plistlib.load(file)
                self.assertEqual(entitlements, {"com.apple.security.application-groups": ["$(POMODORO_APP_GROUP)"]})
        for settings in self.settings("PomodoroNative"):
            self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], "$(POMODORO_NATIVE_BUNDLE_ID)")
            self.assertEqual(settings["GENERATE_INFOPLIST_FILE"], "YES")
            with (ROOT / settings["INFOPLIST_FILE"]).open("rb") as file:
                info = plistlib.load(file)
            self.assertIs(info["NSSupportsLiveActivities"], True)
            self.assertEqual(info["PomodoroAppGroup"], "$(POMODORO_APP_GROUP)")
        for settings in self.settings("PomodoroWidgets"):
            self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], "$(POMODORO_WIDGET_BUNDLE_ID)")
            self.assertEqual(settings["APPLICATION_EXTENSION_API_ONLY"], "YES")
            self.assertEqual(settings["SKIP_INSTALL"], "YES")
        for settings in self.settings("Pomodoro"):
            self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], "com.example.Pomodoro")
            self.assertNotIn("CODE_SIGN_ENTITLEMENTS", settings)
            self.assertNotIn("INFOPLIST_KEY_NSSupportsLiveActivities", settings)
            self.assertNotIn("SWIFT_ACTIVE_COMPILATION_CONDITIONS", settings)

    def test_extension_plist_and_version_match_host(self):
        with (ROOT / "PomodoroWidgets/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        self.assertEqual(info["NSExtension"], {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"})
        self.assertEqual(info["CFBundlePackageType"], "XPC!")
        self.assertEqual(info["CFBundleIdentifier"], "$(PRODUCT_BUNDLE_IDENTIFIER)")
        self.assertEqual(info["CFBundleShortVersionString"], "$(MARKETING_VERSION)")
        self.assertEqual(info["CFBundleVersion"], "$(CURRENT_PROJECT_VERSION)")
        self.assertEqual(info["PomodoroAppGroup"], "$(POMODORO_APP_GROUP)")
        for host, extension in zip(self.settings("PomodoroNative"), self.settings("PomodoroWidgets")):
            self.assertEqual(host["MARKETING_VERSION"], extension["MARKETING_VERSION"])
            self.assertEqual(host["CURRENT_PROJECT_VERSION"], extension["CURRENT_PROJECT_VERSION"])

    def test_overridable_defaults_and_debug_flags(self):
        configurations = [item for item in self.objects.values() if item["isa"] == "XCBuildConfiguration"]
        project = [item for item in configurations if "SDKROOT" in item["buildSettings"]]
        self.assertEqual(len(project), 2)
        for config in project:
            settings = config["buildSettings"]
            self.assertEqual(settings["IPHONEOS_DEPLOYMENT_TARGET"], "17.0")
            self.assertEqual(settings["POMODORO_NATIVE_BUNDLE_ID"], "com.example.Pomodoro.Native")
            self.assertEqual(settings["POMODORO_WIDGET_BUNDLE_ID"], "$(POMODORO_NATIVE_BUNDLE_ID).Widgets")
            self.assertEqual(settings["POMODORO_APP_GROUP"], "group.$(POMODORO_NATIVE_BUNDLE_ID)")
            if config["name"] == "Debug":
                self.assertEqual(settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"], "DEBUG")

    def test_shared_schemes_keep_existing_tests_and_launch_correct_app(self):
        for name in ("Pomodoro", "PomodoroNative"):
            root = ET.parse(ROOT / f"Pomodoro.xcodeproj/xcshareddata/xcschemes/{name}.xcscheme").getroot()
            builds = root.findall("BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference")
            launches = root.findall("LaunchAction/BuildableProductRunnable/BuildableReference")
            self.assertEqual([item.get("BuildableName") for item in builds], [name + ".app"])
            self.assertEqual([item.get("BuildableName") for item in launches], [name + ".app"])
            tests = root.findall("TestAction/Testables/TestableReference/BuildableReference")
            self.assertEqual([item.get("BlueprintName") for item in tests],
                             ["PomodoroTests", "PomodoroUITests"] if name == "Pomodoro" else ["PomodoroNativeTests"])

    def test_regeneration_is_deterministic(self):
        paths = [ROOT / "Pomodoro.xcodeproj/project.pbxproj",
                 ROOT / "Pomodoro.xcodeproj/xcshareddata/xcschemes/Pomodoro.xcscheme",
                 ROOT / "Pomodoro.xcodeproj/xcshareddata/xcschemes/PomodoroNative.xcscheme"]
        before = {path: path.read_bytes() for path in paths}
        runpy.run_path(str(ROOT / "Scripts/generate_project.py"))
        self.assertEqual(before, {path: path.read_bytes() for path in paths})

    def test_each_app_registers_only_its_own_url_scheme(self):
        for name, scheme in (("Pomodoro", "pomodoro"), ("PomodoroNative", "pomodoro-native")):
            for settings in self.settings(name):
                with (ROOT / settings["INFOPLIST_FILE"]).open("rb") as file:
                    info = plistlib.load(file)
                types = info["CFBundleURLTypes"]
                self.assertEqual([value for entry in types for value in entry["CFBundleURLSchemes"]], [scheme])
        with (ROOT / "PomodoroWidgets/Info.plist").open("rb") as file:
            self.assertNotIn("CFBundleURLTypes", plistlib.load(file))

    def test_original_sounds_are_short_pcm_and_bundled_in_both_apps(self):
        paths = {f"Pomodoro/Sounds/{name}.wav" for name in ("bell", "chime", "softTap", "digital")}
        for path in paths:
            with wave.open(str(ROOT / path), "rb") as sound:
                self.assertEqual((sound.getnchannels(), sound.getsampwidth(), sound.getframerate()), (1, 2, 44100))
                self.assertLessEqual(sound.getnframes() / sound.getframerate(), 5)
        for name in ("Pomodoro", "PomodoroNative"):
            resources = {self.objects[self.objects[value]["fileRef"]]["path"]
                         for phase in self.phases(name, "PBXResourcesBuildPhase") for value in phase["files"]}
            self.assertTrue(paths.issubset(resources))


if __name__ == "__main__":
    unittest.main()
