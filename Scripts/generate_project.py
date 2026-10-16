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


groups = []
products = []
targets = []
project_id = uid("project")
app_target = uid("Pomodoro.target")
for name, patterns, product_type in [
    ("Pomodoro", ["Pomodoro/**/*.swift"], "application"),
    ("PomodoroTests", ["Tests/Core/*.swift", "Tests/App/*.swift"], "bundle.unit-test"),
    ("PomodoroUITests", ["Tests/UI/*.swift"], "bundle.ui-testing")
]:
    children, sources = [], []
    for path in sorted({path for pattern in patterns for path in ROOT.glob(pattern)}):
        relative = path.relative_to(ROOT).as_posix()
        ref = add(relative, isa="PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
        children.append(ref)
        sources.append(add(relative + ".build", isa="PBXBuildFile", fileRef=ref))
    resources = []
    if name == "Pomodoro":
        ref = add("assets", isa="PBXFileReference", lastKnownFileType="folder.assetcatalog", path="Pomodoro/Assets.xcassets", sourceTree="SOURCE_ROOT")
        children.append(ref)
        resources.append(add("assets.build", isa="PBXBuildFile", fileRef=ref))
    groups.append(add(name + "group", isa="PBXGroup", children=children, name=name, sourceTree="<group>"))
    extension = "app" if name == "Pomodoro" else "xctest"
    product = add(name + "product", isa="PBXFileReference", explicitFileType="wrapper.application" if extension == "app" else "wrapper.cfbundle",
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
    if name == "Pomodoro":
        settings.update({"MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "1",
                         "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                         "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
                         "INFOPLIST_KEY_CFBundleDisplayName": "Pomodoro",
                         "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
                         "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
                         "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                         "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"})
    else:
        proxy = add(name + "proxy", isa="PBXContainerItemProxy", containerPortal=project_id, proxyType=1,
                    remoteGlobalIDString=app_target, remoteInfo="Pomodoro")
        dependencies.append(add(name + "dependency", isa="PBXTargetDependency", target=app_target, targetProxy=proxy))
        if name == "PomodoroTests":
            settings.update({"BUNDLE_LOADER": "$(TEST_HOST)", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Pomodoro.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Pomodoro"})
        else:
            settings["TEST_TARGET_NAME"] = "Pomodoro"
    targets.append(add(name + ".target", isa="PBXNativeTarget", buildConfigurationList=configurations(name, settings),
                       buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, productName=name,
                       productReference=product, productType="com.apple.product-type." + product_type))

groups.append(add("products", isa="PBXGroup", children=products, name="Products", sourceTree="<group>"))
main = add("main", isa="PBXGroup", children=groups, sourceTree="<group>")
project_configs = configurations("project", {
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
    "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "SWIFT_STRICT_CONCURRENCY": "targeted", "ENABLE_USER_SCRIPT_SANDBOXING": "YES"
})
add("project", isa="PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "2600"},
    buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en",
    hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main, productRefGroup=uid("products"),
    projectDirPath="", projectRoot="", targets=targets)

project_dir = ROOT / "Pomodoro.xcodeproj"
project_dir.mkdir(exist_ok=True)
(project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project_id}) + "\n")


def reference(name):
    extension = "app" if name == "Pomodoro" else "xctest"
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name + ".target")}" BuildableName="{name}.{extension}" BlueprintName="{name}" ReferencedContainer="container:Pomodoro.xcodeproj"/>'


scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
  <BuildActionEntries>
   <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference("Pomodoro")}</BuildActionEntry>
  </BuildActionEntries>
 </BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
  <Testables>
   <TestableReference skipped="NO">{reference("PomodoroTests")}</TestableReference>
   <TestableReference skipped="NO">{reference("PomodoroUITests")}</TestableReference>
  </Testables>
 </TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
  <BuildableProductRunnable runnableDebuggingMode="0">{reference("Pomodoro")}</BuildableProductRunnable>
 </LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
  <BuildableProductRunnable runnableDebuggingMode="0">{reference("Pomodoro")}</BuildableProductRunnable>
 </ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = project_dir / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / "Pomodoro.xcscheme").write_text(scheme)
print(f"Generated project with {len(targets)} targets and {len(objects)} objects.")
