#!/usr/bin/env python3
"""Assemble the native Mac host around a pinned upstream binary release. No downloads."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import stat
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "upstream.json").read_text())


def sha256(path):
    with open(path, "rb") as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_input(path, expected):
    if sha256(path) != expected:
        raise ValueError(f"SHA-256 mismatch: {path}")


def extract_zip(path, destination):
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            name = PurePosixPath(entry.filename)
            if (name.is_absolute() or ".." in name.parts or "\\" in entry.filename
                    or stat.S_ISLNK(entry.external_attr >> 16)):
                raise ValueError(f"Unsafe ZIP entry: {entry.filename}")
        archive.extractall(destination)
        for entry in archive.infolist():
            target = destination / entry.filename
            if target.is_file():
                target.chmod(0o755 if (entry.external_attr >> 16) & 0o111 else 0o644)


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def is_macho(path):
    with path.open("rb") as stream:
        return stream.read(4) in (b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")


def build(upstream, baseline, output):
    verify_input(upstream, CONFIG["sha256"])
    verify_input(baseline, CONFIG["baseline_sha256"])
    if output.exists():
        raise ValueError(f"Output already exists; choose an empty destination: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Keep failed/partial builds away from the final output directory.
    with tempfile.TemporaryDirectory(prefix="unora-build-", dir=output.parent) as temporary:
        stage = Path(temporary)
        extract_zip(upstream, stage / "upstream")
        extract_zip(baseline, stage / "baseline")
        old_apps = [p for p in (stage / "baseline").rglob("Unora Launcher.app")
                    if (p / "Contents/Info.plist").is_file() and "__MACOSX" not in p.parts]
        if len(old_apps) != 1:
            raise ValueError("Expected exactly one baseline app")
        old_resources = old_apps[0] / "Contents/Resources"
        if sha256(old_resources / "AppIcon.icns") != sha256(ROOT / "macos/AppIcon.icns"):
            raise ValueError("The preserved app icon does not match the baseline")
        result = stage / "result"
        package = result / "Unora Launcher for macOS"
        app = package / "Unora Launcher.app"
        contents = app / "Contents"
        resources = contents / "Resources"
        executable = contents / "MacOS/UnoraLauncher"
        executable.parent.mkdir(parents=True)
        resources.mkdir()
        shutil.copy2(ROOT / "macos/Info.plist", contents / "Info.plist")
        plist = plistlib.loads((contents / "Info.plist").read_bytes())
        if plist["UnoraSeedVersion"] != CONFIG["version"]:
            raise ValueError("Info.plist seed version does not match upstream.json")
        shutil.copy2(ROOT / "macos/AppIcon.icns", resources / "AppIcon.icns")
        # Reuse the exact Microsoft ARM64 runtime already distributed in mac1.
        shutil.copytree(old_resources / "dotnet", resources / "dotnet")
        launcher = resources / "Launcher"
        version = launcher / "versions" / CONFIG["version"]
        source = stage / "upstream/versions" / CONFIG["version"]
        version.mkdir(parents=True)
        for path in source.rglob("*"):
            if not path.is_file():
                continue
            relative = path.relative_to(source)
            # Preserve managed dependencies verbatim; omit other OS native payloads.
            if relative.parts[0] == "runtimes" and relative.parts[1] != "osx":
                continue
            target = version / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
        shutil.copy2(stage / "upstream/run.sh", launcher / "run.sh")
        (launcher / "run.sh").chmod(0o755)
        native = version / "runtimes/osx/native"
        for library in sorted(native.glob("*.dylib")):
            arm64 = library.with_suffix(".arm64")
            run("lipo", library, "-thin", "arm64", "-output", arm64)
            arm64.replace(library)
        run("xcrun", "clang", "-fobjc-arc", "-fblocks", "-arch", "arm64",
            "-mmacosx-version-min=12.0", "-Wall", "-Wextra", "-Werror",
            "-Wno-unused-parameter", "-framework", "Cocoa",
            ROOT / "macos/UnoraLauncherHost.m", "-o", executable)
        for path in sorted(resources.rglob("*")):
            if path.is_file() and is_macho(path):
                run("codesign", "--force", "--sign", "-", "--timestamp=none", path)
                run("codesign", "--verify", "--strict", path)
        run("codesign", "--force", "--sign", "-", "--timestamp=none", app)
        run("codesign", "--verify", "--deep", "--strict", app)
        run("plutil", "-lint", contents / "Info.plist")
        run(resources / "dotnet/dotnet", "--list-runtimes")
        shutil.copy2(ROOT / "README.md", package / "README.md")
        inventory = {str(p.relative_to(app)): sha256(p)
                     for p in sorted(app.rglob("*")) if p.is_file()}
        (result / "build-manifest.json").write_text(json.dumps({
            "upstream": CONFIG, "files": inventory,
        }, indent=2) + "\n")
        archive = result / "unora-launcher.apple.silicon.zip"
        run("ditto", "--norsrc", "-c", "-k", "--keepParent", package, archive)
        (result / "SHA256SUMS").write_text(f"{sha256(archive)}  {archive.name}\n")
        result.rename(output)
    print(f"Built {output / archive.name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    build(args.upstream.resolve(), args.baseline.resolve(), args.output.resolve())
