#!/usr/bin/env python3
"""
Bump MARKETING_VERSION in Loopmural.xcodeproj/project.pbxproj.

Usage:
    python3 bump_version.py [patch|minor|major]

The script reads the current version from the pbxproj, increments it
according to the action, and writes the result back.

Targets updated:
  - macOS app (com.kinn.Loopmural)
  - Unit Tests (com.kinn.LoopmuralTests)
  - UI Tests (com.kinn.LoopmuralUITests)

Testing:
python3 .github/scripts/bump_version.py patch   # 1.0.0 → 1.0.1
python3 .github/scripts/bump_version.py minor   # 1.0.0 → 1.1.0
python3 .github/scripts/bump_version.py major   # 1.0.0 → 2.0.0
"""

import os
import re
import sys

PBXPROJ = os.path.join(
    os.path.dirname(__file__),
    "../../Loopmural.xcodeproj/project.pbxproj",
)

TARGETS = [
    # macOS app
    r"com\.kinn\.Loopmural;",
    # Test targets
    r"com\.kinn\.LoopmuralTests;",
    r"com\.kinn\.LoopmuralUITests;",
]


def bump(action: str) -> str:
    with open(PBXPROJ, "r") as f:
        content = f.read()

    # Read current version from the first MARKETING_VERSION occurrence
    m = re.search(r"MARKETING_VERSION = (\d+(?:\.\d+)+);", content)
    if not m:
        sys.exit("ERROR: Could not find MARKETING_VERSION in project.pbxproj")

    current = m.group(1)
    parts = list(map(int, current.split(".")))
    while len(parts) < 3:
        parts.append(0)
    major, minor, patch = parts[:3]

    if action == "major":
        major += 1
        minor = 0
        patch = 0
    elif action == "minor":
        minor += 1
        patch = 0
    elif action == "patch":
        patch += 1
    else:
        sys.exit(f"ERROR: Unknown action '{action}'. Use patch, minor, or major.")

    new_version = f"{major}.{minor}.{patch}"
    print(f"Version: {current} -> {new_version}")

    for bundle_pattern in TARGETS:
        content, n = re.subn(
            rf"(MARKETING_VERSION = )\d+(?:\.\d+)+(;\s*\n\s*PRODUCT_BUNDLE_IDENTIFIER = {bundle_pattern})",
            rf"\g<1>{new_version}\2",
            content,
        )
        if n == 0:
            print(f"WARNING: no match for bundle pattern: {bundle_pattern}", flush=True)

    with open(PBXPROJ, "w") as f:
        f.write(content)

    print(f"Done. New version: {new_version}")
    return new_version


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {sys.argv[0]} [patch|minor|major]")
    bump(sys.argv[1])
