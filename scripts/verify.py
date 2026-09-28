#!/usr/bin/env python3
"""Verify the distributable ZIP, signatures, ARM64 binaries and upstream payload."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

from build import CONFIG, extract_zip, is_macho, run, sha256, verify_input


def verify(release, upstream):
    verify_input(upstream, CONFIG["sha256"])
    archive = release / "unora-launcher.apple.silicon.zip"
    expected = (release / "SHA256SUMS").read_text().split()[0]
    verify_input(archive, expected)
    manifest = json.loads((release / "build-manifest.json").read_text())["files"]
    with tempfile.TemporaryDirectory(prefix="unora-verify-") as temporary:
        root = Path(temporary)
        extract_zip(archive, root)
        app = root / "Unora Launcher for macOS/Unora Launcher.app"
        actual = {str(p.relative_to(app)): sha256(p) for p in app.rglob("*") if p.is_file()}
        if actual != manifest:
            raise ValueError("Extracted app differs from the build manifest")
        run("codesign", "--verify", "--deep", "--strict", app)
        run("plutil", "-lint", app / "Contents/Info.plist")
        macho_count = 0
        for path in app.rglob("*"):
            if path.is_file() and is_macho(path):
                architectures = subprocess.check_output(["lipo", "-archs", str(path)], text=True).strip()
                if architectures != "arm64":
                    raise ValueError(f"Expected ARM64 only: {path}: {architectures}")
                run("codesign", "--verify", "--strict", path)
                macho_count += 1
        version = app / "Contents/Resources/Launcher/versions" / CONFIG["version"]
        checked = 0
        with zipfile.ZipFile(upstream) as source:
            for path in version.rglob("*"):
                if not path.is_file() or path.suffix == ".dylib":
                    continue
                relative = str(path.relative_to(version))
                if path.read_bytes() != source.read(f"versions/{CONFIG['version']}/{relative}"):
                    raise ValueError(f"Modified upstream payload: {relative}")
                checked += 1
        if {p.name for p in (version / "runtimes").iterdir()} != {"osx"}:
            raise ValueError("Unexpected non-macOS runtime payload")
        runtime = app / "Contents/Resources/dotnet/dotnet"
        host = app / "Contents/MacOS/UnoraLauncher"
        if not os.access(runtime, os.X_OK) or not os.access(host, os.X_OK):
            raise ValueError("Executable permissions were lost in the ZIP")
        runtime_info = subprocess.check_output([str(runtime), "--info"], text=True)
        if "arm64" not in runtime_info or CONFIG["runtime_version"] not in runtime_info:
            raise ValueError("Unexpected bundled .NET runtime")
        print(f"PASS: archive checksum and {len(actual)} app file hashes")
        print(f"PASS: {macho_count} ARM64 Mach-O signatures and complete app signature")
        print(f"PASS: {checked} upstream managed/config files are byte-identical")
        print("PASS: extracted executables, bundled runtime and macOS-only native payload")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", type=Path, required=True)
    parser.add_argument("--upstream", type=Path, required=True)
    args = parser.parse_args()
    verify(args.release.resolve(), args.upstream.resolve())
