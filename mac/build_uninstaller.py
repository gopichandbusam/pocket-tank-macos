#!/usr/bin/env python3
"""Build the standalone native uninstaller without executing an uninstall."""
import os
from pathlib import Path
import plistlib
import platform
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "dist"

def run(*args):
    subprocess.run([str(value) for value in args], check=True)

def target_settings(output=OUTPUT):
    architecture = platform.machine()
    if architecture not in {"arm64", "x86_64"}:
        raise RuntimeError(f"Unsupported native architecture: {architecture}")
    app_info = output / "Pocket Tank.app/Contents/Info.plist"
    if app_info.is_file():
        with app_info.open("rb") as stream:
            minimum = plistlib.load(stream).get("LSMinimumSystemVersion")
    else:
        minimum = None
    minimum = minimum or platform.mac_ver()[0]
    if not minimum or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", minimum):
        raise RuntimeError(f"Cannot determine valid macOS deployment minimum: {minimum!r}")
    return architecture, minimum


def binary_minimum(path):
    output = subprocess.check_output(["otool", "-l", str(path)], text=True)
    versions = []
    for block in re.split(r"(?=Load command \d+)", output):
        if "cmd LC_BUILD_VERSION" in block:
            match = re.search(r"\bminos\s+([0-9.]+)", block)
        elif "cmd LC_VERSION_MIN_MACOSX" in block:
            match = re.search(r"\bversion\s+([0-9.]+)", block)
        else:
            continue
        if match:
            versions.append(match.group(1))
    if not versions:
        raise RuntimeError(f"Missing macOS deployment version in {path}")
    return max(versions, key=lambda v: tuple(int(p) for p in v.split(".")))


def main():
    architecture, deployment = target_settings()
    OUTPUT.mkdir(exist_ok=True)
    cache = ROOT / "work/swift-module-cache"
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".uninstaller-stage-", dir=OUTPUT) as directory:
        stage = Path(directory) / "Uninstall Pocket Tank.app"
        binary = stage / "Contents/MacOS/PocketTankUninstaller"
        binary.parent.mkdir(parents=True)
        resources = stage / "Contents/Resources"
        resources.mkdir()
        run("swiftc", ROOT / "mac/uninstall.swift", "-framework", "AppKit",
            "-target", f"{architecture}-apple-macos{deployment}", "-module-cache-path", cache, "-o", binary)
        shutil.copy2(OUTPUT / "Pocket Tank.app/Contents/Resources/PocketTank.icns", resources)
        minimum = binary_minimum(binary)
        info = {"CFBundleIdentifier": "com.local.pockettank.uninstaller",
                "CFBundleExecutable": "PocketTankUninstaller", "CFBundleName": "Uninstall Pocket Tank",
                "CFBundleDisplayName": "Uninstall Pocket Tank", "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
                "LSMinimumSystemVersion": minimum, "NSHighResolutionCapable": True,
                "CFBundleIconFile": "PocketTank.icns"}
        with (stage / "Contents/Info.plist").open("wb") as stream:
            plistlib.dump(info, stream)
        run("codesign", "--force", "--deep", "--sign", "-", stage)
        run("codesign", "--verify", "--deep", "--strict", stage)
        run(binary, "--self-test")
        target = OUTPUT / stage.name
        previous = Path(directory) / "previous.app"
        if target.exists():
            os.replace(target, previous)
        try:
            os.replace(stage, target)
        except Exception:
            if previous.exists():
                os.replace(previous, target)
            raise
        print("Built", target)

if __name__ == "__main__":
    main()
