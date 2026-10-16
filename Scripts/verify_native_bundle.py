"""Check the built native app before packaging it for installation."""
from pathlib import Path
import plistlib
import sys


def verify(app):
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


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
    print("Native app contains a matching widget extension and resolved configuration.")
