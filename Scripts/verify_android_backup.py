#!/usr/bin/env python3
"""Verify the Android export against the current Swift backup decoder.

Requires JDK/Android Gradle dependencies and a local swift:6.0.3 Docker image.
The Swift core and repository are mounted read-only. No iOS build is performed.
"""
from pathlib import Path
import argparse
import os
import subprocess
import tempfile

SWIFT_HARNESS = r'''
import Foundation
let original = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let android = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let expected = try BackupService.decode(original)
let actual = try BackupService.decode(android)
guard actual == expected else {
    throw NSError(domain: "BackupPortability", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "Android export differs from the Swift source snapshot"])
}
guard actual.sessions.last!.duration == 49.75,
      actual.projects.first!.createdAt.timeIntervalSinceReferenceDate == 814990000.125,
      actual.thoughts.last!.projectID == nil,
      actual.goalPlan.weeklyProjectRevisions.last!.minutes == nil else {
    throw NSError(domain: "BackupPortability", code: 2,
                  userInfo: [NSLocalizedDescriptionKey: "Fractional dates or optional fields changed"])
}
let reencoded = try BackupService.exportSavedData(actual)
guard try BackupService.decode(reencoded) == expected else {
    throw NSError(domain: "BackupPortability", code: 3)
}
print("PASS: Swift schema-9 fixture -> Kotlin decode/export -> Swift decode; full snapshot equality")
print("PASS: fractional timestamps, Unicode, standalone/completed thoughts, daily/weekly goals, sounds and session plan")
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift-image", default="swift:6.0.3")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    subprocess.run([
        str(root / "android/gradlew"), "-p", str(root / "android"),
        ":core:test", "--tests", "*BackupPortabilityTest*", "--rerun-tasks", "--console=plain",
    ], check=True)
    exported = root / "android/core/build/backup-portability/android-v9.json"
    if not exported.is_file():
        raise RuntimeError("Kotlin portability test did not emit its Android export")
    with tempfile.TemporaryDirectory(prefix="pomodoro-backup-") as directory:
        Path(directory, "main.swift").write_text(SWIFT_HARNESS)
        subprocess.run([
            "docker", "run", "--rm", "--pull=never", "--network", "none",
            "--user", f"{os.getuid()}:{os.getgid()}",
            "-v", f"{root}:/repo:ro", "-v", f"{directory}:/verification",
            args.swift_image, "sh", "-c",
            "swiftc /repo/Pomodoro/Core/*.swift /verification/main.swift -o /verification/verify "
            "&& /verification/verify /repo/android/core/src/test/resources/swift-v9-rich.json "
            "/repo/android/core/build/backup-portability/android-v9.json",
        ], check=True)


if __name__ == "__main__":
    main()
