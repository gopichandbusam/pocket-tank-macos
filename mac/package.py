#!/usr/bin/env python3
"""Build a relocatable Pocket Tank.app bundle from a completed simulator build."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT
DEFAULT_OUTPUT = ROOT / "dist"
IDENTIFIER = "com.local.pockettank"
READ_ME = ROOT / "mac/Read Me.txt"


def run(args: list[str], *, capture: bool = False) -> str:
    result = subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    return result.stdout if capture else ""


def deps(path: Path) -> list[str]:
    output = run(["otool", "-L", str(path)], capture=True)
    return [m.group(1) for line in output.splitlines()[1:]
            if (m := re.match(r"\s*(.*?)\s+\(compatibility version", line))]


def rpaths(path: Path) -> list[str]:
    output = run(["otool", "-l", str(path)], capture=True)
    result: list[str] = []
    lines = output.splitlines()
    for i, line in enumerate(lines):
        if line.strip() == "cmd LC_RPATH":
            for candidate in lines[i + 1:i + 5]:
                match = re.match(r"\s*path (.*?) \(offset", candidate)
                if match:
                    result.append(match.group(1))
                    break
    return result


def resolve_dep(dep: str, owner: Path, executable: Path) -> Path | None:
    if dep.startswith("/System/Library/") or dep.startswith("/usr/lib/"):
        return None
    candidates: list[Path] = []
    if dep.startswith("@loader_path/"):
        candidates.append(owner.parent / dep.removeprefix("@loader_path/"))
    elif dep.startswith("@executable_path/"):
        candidates.append(executable.parent / dep.removeprefix("@executable_path/"))
    elif dep.startswith("@rpath/"):
        suffix = dep.removeprefix("@rpath/")
        for base in dict.fromkeys([*rpaths(owner), *rpaths(executable)]):
            if base.startswith("@loader_path/"):
                candidates.append(owner.parent / base.removeprefix("@loader_path/") / suffix)
            elif base.startswith("@executable_path/"):
                candidates.append(executable.parent / base.removeprefix("@executable_path/") / suffix)
            elif base.startswith("/"):
                candidates.append(Path(base) / suffix)
    elif dep.startswith("/"):
        candidates.append(Path(dep))
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    raise RuntimeError(f"Cannot resolve non-system dependency {dep!r} referenced by {owner}")


def version_tuple(version: str) -> tuple[int, ...]:
    parts = tuple(int(part) for part in version.split("."))
    return parts + (0,) * max(0, 3 - len(parts))


def architectures(path: Path) -> set[str]:
    archs = set(run(["lipo", "-archs", str(path)], capture=True).split())
    if not archs or not archs <= {"arm64", "x86_64"}:
        raise RuntimeError(f"Unsupported architectures for {path}: {sorted(archs)}")
    return archs


def minimum_macos(path: Path) -> str:
    versions = []
    output = run(["otool", "-l", str(path)], capture=True)
    for block in re.split(r"(?=Load command \d+)", output):
        if "cmd LC_BUILD_VERSION" in block:
            if not re.search(r"platform\s+(?:1|MACOS)\b", block):
                raise RuntimeError(f"Non-macOS platform in {path}")
            match = re.search(r"\bminos\s+([0-9.]+)", block)
        elif "cmd LC_VERSION_MIN_MACOSX" in block:
            match = re.search(r"\bversion\s+([0-9.]+)", block)
        else:
            continue
        if match:
            versions.append(match.group(1))
    if not versions:
        raise RuntimeError(f"No macOS deployment minimum found in {path}")
    return max(versions, key=version_tuple)


def dependency_closure(executable: Path, extra: list[Path]) -> list[Path]:
    found = set(extra)
    queue = [executable, *extra]
    while queue:
        owner = queue.pop(0)
        for dep in deps(owner):
            library = resolve_dep(dep, owner, executable)
            if library is not None and library not in found:
                found.add(library)
                queue.append(library)
    return sorted(found)


def sdl_runtime(executable: Path) -> tuple[list[Path], list[Path]]:
    prefix = Path(run(["sdl2-config", "--prefix"], capture=True).strip())
    linked = dependency_closure(executable, [])
    # SDL2-compat loads SDL3 dynamically, which otool cannot discover.
    extra = []
    if any("sdl2-compat" in str(path.resolve()) for path in linked):
        prefixes = [prefix / "opt/sdl3", Path("/opt/homebrew/opt/sdl3"), Path("/usr/local/opt/sdl3")]
        brew = shutil.which("brew")
        if brew:
            result = subprocess.run([brew, "--prefix", "sdl3"], text=True, capture_output=True)
            if result.returncode == 0:
                prefixes.insert(0, Path(result.stdout.strip()))
        for candidate in prefixes:
            library = candidate / "lib/libSDL3.0.dylib"
            if library.is_file():
                extra = [library.resolve()]
                break
        if not extra:
            raise FileNotFoundError("SDL2-compat requires SDL3; no installed runtime found")
    return extra, dependency_closure(executable, extra)


def copy_runtime_licenses(libraries: list[Path], legal: Path) -> None:
    seen = set()
    for library in libraries:
        prefix = library.parent.parent
        if prefix in seen:
            continue
        seen.add(prefix)
        candidates = sorted((prefix / "share/licenses").glob("**/*"))
        candidates += [prefix / name for name in ("LICENSE.txt", "LICENSE", "COPYING.txt", "COPYING")]
        files = [path for path in candidates if path.is_file() and
                 re.search(r"license|licence|copying|copyright", path.name, re.I)]
        if not files:
            raise FileNotFoundError(f"License missing for bundled dependency {library}; searched {prefix}")
        label = prefix.parent.name if prefix.parent.parent.name == "Cellar" else prefix.name
        unique = {}
        for path in files:
            unique.setdefault(hashlib.sha256(path.read_bytes()).hexdigest(), path)
        for index, path in enumerate(unique.values()):
            sdl_label = "SDL2" if library.name.startswith("libSDL2") else "SDL3" if library.name.startswith("libSDL3") else None
            if sdl_label and index == 0:
                destination = legal / f"{sdl_label}-LICENSE.txt"
            else:
                folder = legal / label
                folder.mkdir(exist_ok=True)
                destination = folder / f"{index}-{path.name}"
            shutil.copy2(path, destination)



def bundle_dylibs(executable: Path, frameworks: Path, extra_dylibs: list[Path]) -> list[Path]:
    frameworks.mkdir(parents=True, exist_ok=True)
    original_to_bundled: dict[Path, Path] = {}
    queue: list[tuple[Path, Path]] = [(executable, executable)]
    bundled: list[Path] = []
    for source in extra_dylibs:
        source = source.resolve()
        target = frameworks / source.name
        shutil.copy2(source, target)
        os.chmod(target, 0o755)
        original_to_bundled[source] = target
        bundled.append(target)
        queue.append((source, target))
    while queue:
        owner_original, owner_in_bundle = queue.pop(0)
        for dep in deps(owner_original):
            source = resolve_dep(dep, owner_original, executable)
            if source is None:
                continue
            if source not in original_to_bundled:
                target = frameworks / source.name
                if target.exists() and target.resolve() != source:
                    raise RuntimeError(f"Dylib basename collision for {source.name}")
                if not target.exists():
                    shutil.copy2(source, target)
                    os.chmod(target, 0o755)
                original_to_bundled[source] = target
                bundled.append(target)
                queue.append((source, target))
    # Give each library a local install id and rewrite dependencies for all bundled images.
    for source, target in original_to_bundled.items():
        run(["install_name_tool", "-id", f"@loader_path/{target.name}", str(target)])
    for owner_original, owner_in_bundle in [(executable, executable)] + [
            (source, target) for source, target in original_to_bundled.items()]:
        for dep in deps(owner_original):
            source = resolve_dep(dep, owner_original, executable)
            if source in original_to_bundled:
                name = original_to_bundled[source].name
                replacement = (f"@executable_path/../Frameworks/{name}" if owner_in_bundle == executable
                               else f"@loader_path/{name}")
                if dep != replacement:
                    run(["install_name_tool", "-change", dep, replacement, str(owner_in_bundle)])
    for library in bundled:
        run(["codesign", "--force", "--sign", "-", str(library)])
    # Confirm closure now resolves exclusively to bundled or macOS-provided libraries.
    for image in [executable, *bundled]:
        for dep in deps(image):
            if dep.startswith("/System/Library/") or dep.startswith("/usr/lib/"):
                continue
            if dep.startswith("@executable_path/"):
                resolved = executable.parent / dep.removeprefix("@executable_path/")
            elif dep.startswith("@loader_path/"):
                resolved = image.parent / dep.removeprefix("@loader_path/")
            else:
                raise RuntimeError(f"Unbundled dependency remains in {image}: {dep}")
            if not resolved.exists():
                raise RuntimeError(f"Bundled dependency is missing: {image} -> {dep}")
    return bundled


def generate_icon(iconset: Path, icon_icns: Path) -> None:
    generator = Path(__file__).with_name("make_icon.swift")
    cache = iconset.parent / ".swift-module-cache"
    cache.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["SWIFT_MODULE_CACHE_PATH"] = str(cache)
    env["CLANG_MODULE_CACHE_PATH"] = str(cache)
    subprocess.run(["swift", str(generator), str(iconset)], check=True, env=env)
    shutil.rmtree(cache)
    # sips produces a valid icns directly from the full-resolution generated PNG.
    run(["sips", "-s", "format", "icns", str(iconset / "icon_512x512.png"), "--out", str(icon_icns)])


def build_app(source: Path, app: Path, workspace: Path) -> Path:
    executable_source = source / "sim/fishsim"
    if not executable_source.is_file():
        raise FileNotFoundError(f"Simulator executable is missing: {executable_source}")
    model_dir = source / "model/out"
    sound_file = source / "assets/sounds/sounds.bin"
    required = [model_dir / "model_q4.bin", model_dir / "tokenizer.bin", sound_file]
    missing = [str(p) for p in required if not p.is_file()]
    if missing:
        raise FileNotFoundError("Required app resources are missing: " + ", ".join(missing))
    archs = architectures(executable_source)
    extra_dylibs, runtime_libraries = sdl_runtime(executable_source)
    for library in runtime_libraries:
        if not archs <= architectures(library):
            raise RuntimeError(f"Dependency {library} lacks executable architectures {sorted(archs)}")
    minimum = max([minimum_macos(path) for path in [executable_source, *runtime_libraries]], key=version_tuple)

    contents = app / "Contents"
    macos = contents / "MacOS"
    resources = contents / "Resources"
    frameworks = contents / "Frameworks"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    executable = macos / "PocketTank"
    shutil.copy2(executable_source, executable)
    os.chmod(executable, 0o755)
    shutil.copytree(model_dir, resources / "model/out", dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns(".gitkeep"))
    shutil.copytree(source / "assets/sounds", resources / "assets/sounds", dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("*.wav", "*.csv", "*.tsv"))
    if READ_ME.is_file():
        shutil.copy2(READ_ME, resources / "Pocket Tank - Read Me.txt")
    legal = resources / "Licenses"
    legal.mkdir()
    shutil.copy2(source / "LICENSE", legal / "PocketTank-LICENSE.txt")
    lvgl_license = source / "sim/lvgl/LICENCE.txt"
    shutil.copy2(lvgl_license, legal / "LVGL-LICENCE.txt")
    copy_runtime_licenses(runtime_libraries, legal)

    iconset = workspace / ".PocketTank.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir()
    generate_icon(iconset, resources / "PocketTank.icns")
    shutil.rmtree(iconset)
    info = {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": "PocketTank",
        "CFBundleIconFile": "PocketTank.icns",
        "CFBundleIdentifier": IDENTIFIER,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "Pocket Tank",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.3",
        "CFBundleVersion": "4",
        "LSMinimumSystemVersion": minimum,
        "NSHighResolutionCapable": True,
    }
    with (contents / "Info.plist").open("wb") as stream:
        plistlib.dump(info, stream)
    source_files = sorted([*source.glob("common/**/*.c"), *source.glob("common/**/*.h"),
                           *source.glob("common/**/*.inc"), *source.glob("sim/*.c"),
                           *source.glob("sim/*.h"), *source.glob("sim/*.m"), source / "sim/Makefile"])
    lvgl = source / "sim/lvgl"
    git_root = subprocess.run(["git", "-C", str(lvgl), "rev-parse", "--show-toplevel"], text=True, capture_output=True)
    lvgl_has_git = git_root.returncode == 0 and Path(git_root.stdout.strip()).resolve() == lvgl.resolve()
    lvgl_revision = run(["git", "-C", str(lvgl), "rev-parse", "HEAD"], capture=True).strip() if lvgl_has_git else None
    provenance = {"app_version": info["CFBundleShortVersionString"],
                  "architectures": sorted(archs), "minimum_macos": minimum,
                  "lvgl_revision": lvgl_revision,
                  "lvgl_dirty": bool(run(["git", "-C", str(lvgl), "status", "--porcelain", "--untracked-files=no"], capture=True).strip()) if lvgl_has_git else None,
                  "lvgl_header_sha256": hashlib.sha256((lvgl / "lvgl.h").read_bytes()).hexdigest(),
                  "source_sha256": {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest()
                                    for path in source_files},
                  "resource_sha256": {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest()
                                      for path in required},
                  "upstream_commit": "c57960535d85a3432387b34e4a2c456a7f06be64"}
    (resources / "Build Provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    bundle_dylibs(executable, frameworks, extra_dylibs)
    if extra_dylibs:
        sdl3_alias = frameworks / "libSDL3.dylib"
        if not sdl3_alias.exists():
            sdl3_alias.symlink_to(extra_dylibs[0].name)
    run(["codesign", "--force", "--deep", "--sign", "-", str(app)])
    run(["codesign", "--verify", "--deep", "--strict", str(app)])
    return app


def package(source: Path, output: Path, *, make_zip: bool) -> Path:
    """Build in a sibling staging directory, then swap completed artifacts with rollback."""
    output.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".pockettank-stage-", dir=output))
    staged_app = stage / "Pocket Tank.app"
    staged_zip = stage / "Pocket Tank.zip"
    app = output / "Pocket Tank.app"
    archive = output / "Pocket Tank.zip"
    old_app = stage / ".previous-app"
    old_zip = stage / ".previous-zip"
    old_app_moved = old_zip_moved = new_app_moved = new_zip_moved = False
    try:
        build_app(source, staged_app, stage)
        if make_zip:
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(staged_app), str(staged_zip)])
        try:
            if app.exists() or app.is_symlink():
                os.replace(app, old_app)
                old_app_moved = True
            if make_zip and (archive.exists() or archive.is_symlink()):
                os.replace(archive, old_zip)
                old_zip_moved = True
            os.replace(staged_app, app)
            new_app_moved = True
            if make_zip:
                os.replace(staged_zip, archive)
                new_zip_moved = True
        except Exception:
            if new_zip_moved and (archive.exists() or archive.is_symlink()):
                archive.unlink()
            if new_app_moved and (app.exists() or app.is_symlink()):
                shutil.rmtree(app) if app.is_dir() and not app.is_symlink() else app.unlink()
            if old_app_moved:
                os.replace(old_app, app)
            if old_zip_moved:
                os.replace(old_zip, archive)
            raise
        print(f"Packaged {app}")
        if make_zip:
            print(f"Archive: {archive}")
        return app
    finally:
        if stage.exists():
            shutil.rmtree(stage)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--no-zip", action="store_true", help="build only the .app bundle")
    args = parser.parse_args()
    package(args.source.resolve(), args.output.resolve(), make_zip=not args.no_zip)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"package.py: {error}", file=sys.stderr)
        raise SystemExit(1)
