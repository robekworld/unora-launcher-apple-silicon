RWX'S REALLY COOL (UNOFFICIAL) UNORA LAUNCHER FOR MAC
========================================

System requirements
-------------------
- Apple Silicon Mac (M1 or newer)
- macOS 14 Sonoma or newer for a Microsoft-supported .NET 10 configuration

The native host still targets macOS 12, as before, but macOS 12/13 are unverified
and outside Microsoft's current .NET support matrix. Tested on macOS 15.7.

[Download the Apple Silicon build](https://github.com/robekworld/unora-launcher-apple-silicon/releases/latest)

Install
-------
1. unzip the download
2. drag “Unora Launcher” to Applications
3. on first launch, control-click the app, choose Open, then choose Open again

the extra first-launch step is required because this locally built app is
ad-hoc signed rather than distributed through Apple notarization or whatever

What's included
----------------
- The supplied Chaos/Unora Launcher 4.0.11.0 client
- native macOS app host and app icon
- the official Microsoft .NET 10.0.10 Apple Silicon runtime
- repaired Apple Silicon Avalonia/Skia native libraries

the app is self-contained; a separate .NET installation is not required.
the writable launcher files and future launcher updates are kept in:

  ~/Library/Application Support/Unora Launcher

Existing game settings remain in `~/.config/chaos-launcher`, and launcher data
in `~/.local/share/chaos-launcher` (or your existing XDG locations). Replacing
the app preserves these locations and your chosen game install folder.

IMPORTANTTTTTT compatibility note
----------------------------
the downloaded game client includes native Apple Silicon support and launches
through the .NET runtime bundled with this app. Wine, CrossOver, Whisky, and
Parallels are not required. Steam shortcut integration remains unavailable on
macOS.

Runtime source: https://dotnet.microsoft.com/download/dotnet/10.0

Build and test
--------------
The repository now includes the original Objective-C Mac host, its icon,
packaging code, and upgrade tests. The supplied upstream ZIP contains compiled
.NET assemblies, not C# source; we preserve those assemblies without patching
them. See [the comparison and compatibility notes](docs/upstream-4.0.11.md).

On an Apple Silicon Mac with Python 3 and Xcode Command Line Tools:

```sh
sh scripts/test.sh
python3 scripts/build.py \
  --upstream /path/to/Chaos.Launcher.zip \
  --baseline /path/to/unora-launcher.apple.silicon.zip
```

The baseline must be the ZIP from
[v4.0.3-mac1](https://github.com/robekworld/unora-launcher-apple-silicon/releases/tag/v4.0.3-mac1).
It supplies the exact bundled ARM64 runtime used by the original release.
The upstream archive is also attached to the 4.0.11 Mac release for rebuilding.
Both input hashes are pinned in `upstream.json`; the build refuses other inputs
and never downloads or overwrites an existing output directory. It writes an
ad-hoc-signed app, ZIP, file manifest, and SHA-256 checksum to `dist/`.

```sh
python3 scripts/verify.py --release dist --upstream /path/to/Chaos.Launcher.zip
```

To test without using your normal launcher settings or game install:

```sh
UNORA_LAUNCHER_HOME="$PWD/build/test-profile" \
XDG_CONFIG_HOME="$PWD/build/test-config" \
XDG_DATA_HOME="$PWD/build/test-data" \
  "dist/Unora Launcher for macOS/Unora Launcher.app/Contents/MacOS/UnoraLauncher"
```

Choose a separate game folder in that test profile. `UNORA_LAUNCHER_HOME` alone
only redirects launcher versions; the two XDG variables isolate upstream settings
and data. Close other launcher instances before testing.

[Microsoft's macOS support matrix](https://learn.microsoft.com/en-us/dotnet/core/install/macos)

-love rwx
