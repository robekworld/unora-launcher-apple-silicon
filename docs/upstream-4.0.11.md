# Chaos 4.0.11.0 / Apple Silicon mac1

## Inputs and scope

- Repository baseline: `c9d07e6fdcb72759ec266242592d995914105400` (README only).
- Published Mac baseline: `v4.0.3-mac1`, `unora-launcher.apple.silicon.zip`.
- New upstream: supplied `Chaos.Launcher.zip`, version `4.0.11.0`, archive entries dated September 27, 2026.
- Exact input SHA-256 values are pinned in `upstream.json`.

The downloaded GitHub baseline ZIP matches the retained local release byte for
byte. The host source was recovered from that release's original local build
workspace. The icon is byte-identical to the published baseline. No source project
is included in the new upstream archive: this is a binary integration and a native
host rebuild, not a claim to rebuild Chaos's managed assemblies from C#.

## Archive comparison

The old Mac version directory contains 99 files; the new portable version contains
123. Seven common paths differ:

| File | Treatment |
| --- | --- |
| `Chaos.Launcher.App.dll` | Ship the upstream assembly unchanged |
| `Chaos.Launcher.Core.dll` | Ship the upstream assembly unchanged |
| `Chaos.Launcher.Platform.dll` | Ship the upstream assembly unchanged |
| `Chaos.Launcher.App.deps.json` | Ship unchanged; application version advances from 4.0.3.0 to 4.0.11.0 |
| `runtimes/osx/native/libAvaloniaNative.dylib` | Extract ARM64 and ad-hoc sign |
| `runtimes/osx/native/libHarfBuzzSharp.dylib` | Extract ARM64 and ad-hoc sign |
| `runtimes/osx/native/libSkiaSharp.dylib` | Extract ARM64 and ad-hoc sign |

All other shared file contents match. Third-party dependency versions and the
`.NET 10` runtime configuration are unchanged. The upstream `run.sh` is unchanged.
The 26 additional paths are Windows/Linux runtime payloads, excluded from the Mac
package. The two removed files are Core/Platform PDB symbols, absent upstream.
The root Windows EXE and managed bootstrapper are omitted in favor of the native
Mac host, as in the previous Mac release. Full hashes and path lists are in
`upstream-diff.json`.

The original universal upstream libraries pass macOS signature verification outside
the tool sandbox. Restricted verification reported invalid ARM64 signatures for
HarfBuzz and Skia; this was a sandbox artifact, not a confirmed upstream defect.
Build-time ARM64 extraction and signing preserve the established Mac packaging.
No runtime signature-repair subprocess is added.

Targeted local decompilation was used only to inspect compatibility behavior;
decompiled code is not added to the repository. `PlatformService`, `GameLauncher`,
and `VersionedDirectoryUpdateInstaller` retain the same Mac-relevant behavior:
XDG config/data directories, `dotnet Chaos.Client.dll`, and relaunching
`Environment.ProcessPath` with the new launcher DLL as an argument.

## Mac compatibility preserved and fixed

- ARM64 Cocoa host, app identity, icon, menu branding, and bundle layout.
- Bundled .NET 10.0.10 ARM64 runtime; no system .NET, Wine, or Rosetta needed.
- Bundled `dotnet` remains first on child-process PATH for native game launch.
- Writable launcher versions remain under Application Support, outside the app.
- Existing config, saved characters, and game directories retain upstream paths.
- Select the newest complete numeric version; skip staging/incomplete versions.
- Seed new versions through a temporary directory and rename only when complete.
- Recover incomplete seed files under `Launcher/recovered/`, outside upstream's
  version cleanup directory. Do not overwrite an already-complete installation.
- Normalize the DLL argument passed when upstream restarts the native host.

## Limits

- Steam shortcut creation is explicitly Linux-only upstream and remains unavailable
  on macOS. Windows-native and Linux-native components are not ported into this app.
- The app is ad-hoc signed, not Apple-notarized; first launch requires macOS approval.
- The host retains its macOS 12 deployment target, but this release is tested on
  macOS 15.7 ARM64. Microsoft's supported .NET 10 matrix currently starts at macOS 14;
  macOS 12/13 and Intel Macs are not validated.
- Managed-source builds/tests cannot run from this binary-only upstream attachment.
- Future self-update downloads depend on the upstream server and payload format;
  local restart tests do not establish compatibility with unshipped versions.

See `validation.md` for the executed checks and remaining runtime test limits.
