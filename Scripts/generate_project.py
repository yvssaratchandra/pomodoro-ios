#!/usr/bin/env python3
"""Generate the checked-in Xcode project without third-party tools."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def add(identifier, **values):
    key = uid(identifier)
    if key in objects and objects[key] != values:
        raise ValueError(f"Conflicting project object: {identifier}")
    objects[key] = values
    return key


def serialize(value, depth=0):
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            lines.append("\t" * (depth + 1) + json.dumps(key) + " = " + serialize(item, depth + 1) + ";")
        return "\n".join(lines) + "\n" + "\t" * depth + "}"
    if isinstance(value, list):
        return "(" + ", ".join(serialize(item, depth) for item in value) + ")"
    return json.dumps(str(value))


def configurations(name, settings):
    refs = []
    for configuration in ["Debug", "Release"]:
        values = dict(settings)
        if name == "project":
            values.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if configuration == "Debug" else "-O",
                           "DEBUG_INFORMATION_FORMAT": "dwarf" if configuration == "Debug" else "dwarf-with-dsym"})
            if configuration == "Debug":
                values.update({"ENABLE_TESTABILITY": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
                               "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"]})
        refs.append(add(name + configuration, isa="XCBuildConfiguration", buildSettings=values, name=configuration))
    return add(name + "configs", isa="XCConfigurationList", buildConfigurations=refs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


TARGETS = [
    ("Pomodoro", ["Pomodoro/**/*.swift"], "application"),
    ("PomodoroNative", ["Pomodoro/**/*.swift", "Shared/Native/**/*.swift"], "application"),
    ("PomodoroWidgets", ["PomodoroWidgets/**/*.swift", "Shared/Native/**/*.swift",
                         "Pomodoro/Core/Models.swift", "Pomodoro/Core/ExternalSurfaces.swift",
                         "Pomodoro/Core/WidgetSnapshotFile.swift"], "app-extension"),
    ("PomodoroTests", ["Tests/Core/*.swift", "Tests/App/*.swift"], "bundle.unit-test"),
    ("PomodoroUITests", ["Tests/UI/*.swift"], "bundle.ui-testing"),
]
PRODUCT_EXTENSIONS = {name: "app" if kind == "application" else "appex" if kind == "app-extension" else "xctest"
                      for name, _, kind in TARGETS}


def file_reference(path, file_type):
    return add(path, isa="PBXFileReference", lastKnownFileType=file_type, path=path, sourceTree="SOURCE_ROOT")


def dependency(owner, target):
    proxy = add(owner + "." + target + ".proxy", isa="PBXContainerItemProxy", containerPortal=uid("project"),
                proxyType=1, remoteGlobalIDString=uid(target + ".target"), remoteInfo=target)
    return add(owner + "." + target + ".dependency", isa="PBXTargetDependency",
               target=uid(target + ".target"), targetProxy=proxy)


groups, products, targets = [], [], []
project_id = uid("project")
for name, patterns, product_type in TARGETS:
    children, sources = [], []
    for path in sorted({path for pattern in patterns for path in ROOT.glob(pattern)}):
        relative = path.relative_to(ROOT).as_posix()
        ref = file_reference(relative, "sourcecode.swift")
        children.append(ref)
        sources.append(add(name + ".source." + relative, isa="PBXBuildFile", fileRef=ref))
    resources = []
    if product_type == "application":
        ref = file_reference("Pomodoro/Assets.xcassets", "folder.assetcatalog")
        children.append(ref)
        resources.append(add(name + ".assets", isa="PBXBuildFile", fileRef=ref))
    elif name == "PomodoroTests":
        ref = file_reference("Tests/Core/Fixtures", "folder")
        children.append(ref)
        resources.append(add(name + ".fixtures", isa="PBXBuildFile", fileRef=ref))
    groups.append(add(name + "group", isa="PBXGroup", children=children, name=name, sourceTree="<group>"))
    extension = PRODUCT_EXTENSIONS[name]
    product_file_type = {"app": "wrapper.application", "appex": "wrapper.app-extension", "xctest": "wrapper.cfbundle"}[extension]
    product = add(name + "product", isa="PBXFileReference", explicitFileType=product_file_type,
                  includeInIndex=0, path=f"{name}.{extension}", sourceTree="BUILT_PRODUCTS_DIR")
    products.append(product)
    phases = [add(name + "sources", isa="PBXSourcesBuildPhase", buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0),
              add(name + "frameworks", isa="PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0),
              add(name + "resources", isa="PBXResourcesBuildPhase", buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)]
    settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.example." + name,
                "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic",
                "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
                "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
                "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"]}
    dependencies = []
    if product_type in ("application", "app-extension"):
        settings.update({"MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "1"})
    if product_type == "application":
        settings.update({"ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                         "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                         "INFOPLIST_KEY_CFBundleDisplayName": "Pomodoro",
                         "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
                         "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
                         "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                         "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"})
        if name == "Pomodoro":
            settings["INFOPLIST_FILE"] = "Config/Pomodoro-Info.plist"
    if name in ("PomodoroNative", "PomodoroWidgets"):
        settings.update({"SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["$(inherited)", "NATIVE_INTEGRATIONS"],
                         "CODE_SIGN_ENTITLEMENTS": "Config/" + name + ".entitlements"})
    if name == "PomodoroNative":
        settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "$(POMODORO_NATIVE_BUNDLE_ID)",
                         "INFOPLIST_FILE": "Config/PomodoroNative-Info.plist"})
        dependencies.append(dependency(name, "PomodoroWidgets"))
        embedded = add(name + ".embed-widgets", isa="PBXBuildFile", fileRef=uid("PomodoroWidgetsproduct"),
                       settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
        phases.append(add(name + ".embed-extensions", isa="PBXCopyFilesBuildPhase", buildActionMask=2147483647,
                          dstPath="", dstSubfolderSpec=13, files=[embedded], name="Embed App Extensions",
                          runOnlyForDeploymentPostprocessing=0))
    elif name == "PomodoroWidgets":
        settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "$(POMODORO_WIDGET_BUNDLE_ID)",
                         "APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES",
                         "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "PomodoroWidgets/Info.plist",
                         "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]})
    elif product_type.startswith("bundle."):
        dependencies.append(dependency(name, "Pomodoro"))
        if name == "PomodoroTests":
            settings.update({"BUNDLE_LOADER": "$(TEST_HOST)", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Pomodoro.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Pomodoro"})
        else:
            settings["TEST_TARGET_NAME"] = "Pomodoro"
    targets.append(add(name + ".target", isa="PBXNativeTarget", buildConfigurationList=configurations(name, settings),
                       buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, productName=name,
                       productReference=product, productType="com.apple.product-type." + product_type))

config_files = [file_reference("Config/PomodoroNative.entitlements", "text.plist.entitlements"),
                file_reference("Config/Pomodoro-Info.plist", "text.plist.xml"),
                file_reference("Config/PomodoroWidgets.entitlements", "text.plist.entitlements"),
                file_reference("Config/PomodoroNative-Info.plist", "text.plist.xml"),
                file_reference("PomodoroWidgets/Info.plist", "text.plist.xml")]
groups.append(add("configuration", isa="PBXGroup", children=config_files, name="Configuration", sourceTree="<group>"))
groups.append(add("products", isa="PBXGroup", children=products, name="Products", sourceTree="<group>"))
main = add("main", isa="PBXGroup", children=groups, sourceTree="<group>")
project_configs = configurations("project", {
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
    "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "SWIFT_STRICT_CONCURRENCY": "targeted", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "POMODORO_NATIVE_BUNDLE_ID": "com.example.Pomodoro.Native",
    "POMODORO_WIDGET_BUNDLE_ID": "$(POMODORO_NATIVE_BUNDLE_ID).Widgets",
    "POMODORO_APP_GROUP": "group.$(POMODORO_NATIVE_BUNDLE_ID)"
})
add("project", isa="PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2600"},
    buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en",
    hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main, productRefGroup=uid("products"),
    projectDirPath="", projectRoot="", targets=targets)

project_dir = ROOT / "Pomodoro.xcodeproj"
project_dir.mkdir(exist_ok=True)
(project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project_id}) + "\n")


def reference(name):
    extension = PRODUCT_EXTENSIONS[name]
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name + ".target")}" BuildableName="{name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:Pomodoro.xcodeproj"/>'


def scheme(name, test_targets):
    testables = "\n".join(f'   <TestableReference skipped="NO">{reference(target)}</TestableReference>' for target in test_targets)
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
  <BuildActionEntries>
   <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(name)}</BuildActionEntry>
  </BuildActionEntries>
 </BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
  <Testables>
{testables}
  </Testables>
 </TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
  <BuildableProductRunnable runnableDebuggingMode="0">{reference(name)}</BuildableProductRunnable>
 </LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
  <BuildableProductRunnable runnableDebuggingMode="0">{reference(name)}</BuildableProductRunnable>
 </ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''


scheme_dir = project_dir / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
for name, tests in [("Pomodoro", ["PomodoroTests", "PomodoroUITests"]), ("PomodoroNative", [])]:
    (scheme_dir / f"{name}.xcscheme").write_text(scheme(name, tests))
print(f"Generated project with {len(targets)} targets and {len(objects)} objects.")
