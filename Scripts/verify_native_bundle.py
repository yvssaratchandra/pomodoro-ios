"""Check the built native app before packaging it for installation."""
from pathlib import Path
import plistlib
import sys
import subprocess
from tempfile import TemporaryDirectory


def verify_configuration(app):
    with (app / "Info.plist").open("rb") as file:
        host = plistlib.load(file)
    extension = app / "PlugIns/PomodoroWidgets.appex"
    with (extension / "Info.plist").open("rb") as file:
        widget = plistlib.load(file)
    if host.get("NSSupportsLiveActivities") is not True:
        raise ValueError("Native app must declare Live Activity support as a Boolean.")
    group = host.get("PomodoroAppGroup")
    if not isinstance(group, str) or not group.startswith("group.") or "$" in group:
        raise ValueError("Native app has no resolved App Group identifier.")
    if widget.get("PomodoroAppGroup") != group:
        raise ValueError("App and extension App Group identifiers differ.")
    if widget.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
        raise ValueError("Embedded extension is not a WidgetKit extension.")
    host_id = host.get("CFBundleIdentifier")
    widget_id = widget.get("CFBundleIdentifier")
    if (not isinstance(host_id, str) or not host_id or "$" in host_id
            or not isinstance(widget_id, str) or "$" in widget_id
            or not widget_id.startswith(host_id + ".")):
        raise ValueError("Widget bundle identifier must extend the native app identifier.")
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        if not host.get(key) or host[key] != widget.get(key):
            raise ValueError(f"App and extension {key} values must match.")

    return group, (extension, app)


def read_entitlements(bundle):
    result = subprocess.run(["codesign", "--display", "--entitlements", ":-", str(bundle)],
                            check=True, capture_output=True)
    return plistlib.loads(result.stdout)


def verify(app, signature_reader=read_entitlements):
    group, bundles = verify_configuration(app)
    for bundle in bundles:
        permissions = signature_reader(bundle)
        if permissions.get("com.apple.security.application-groups") != [group]:
            raise ValueError(f"{bundle.name} signature must declare exactly the configured App Group.")
        if signature_reader is read_entitlements:
            subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)


def prepare(app):
    group, bundles = verify_configuration(app)
    with TemporaryDirectory() as temporary:
        entitlements = Path(temporary) / "WidgetGroups.plist"
        with entitlements.open("wb") as file:
            plistlib.dump({"com.apple.security.application-groups": [group]}, file)
        # Sign the embedded extension before sealing its containing application.
        for bundle in bundles:
            subprocess.run(["codesign", "--force", "--sign", "-", "--generate-entitlement-der",
                            "--entitlements", str(entitlements), str(bundle)], check=True)
    verify(app)


if __name__ == "__main__":
    if sys.argv[1] == "--prepare":
        prepare(Path(sys.argv[2]))
    elif sys.argv[1] == "--configuration-only":
        verify_configuration(Path(sys.argv[2]))
    else:
        verify(Path(sys.argv[1]))
    print("Native app configuration verified." if sys.argv[1] == "--configuration-only"
          else "Native app and widget signatures declare the same resolved App Group.")
