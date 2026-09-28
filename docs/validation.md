# Local validation — 4.0.11 mac1

Environment: Apple Silicon, macOS 15.7, Apple clang from Xcode Command Line
Tools. Launcher and game used the bundled .NET 10.0.10 runtime. The task machine
also has an SDK, but GUI tests started with PATH restricted to system directories;
the Mac host supplied its bundled dotnet to the child game process.

## Automated checks

- `sh scripts/test.sh`: two Python input-validation tests and nine native host
  assertions pass. Native code compiles with warnings treated as errors.
- Hash mismatch, archive traversal, and ZIP symlink inputs are rejected.
- Host checks cover fresh install with spaces in its path, numeric version order,
  incomplete/staging fallback, keeping newer versions, preserving settings and
  complete payloads, interrupted-seed repair, recovery backup, missing seed failure,
  valid version names, and updater restart arguments.
- `scripts/build.py` compiles the host and assembles/signs the app successfully.
- `scripts/verify.py` extracts the release ZIP and verifies its checksum, all 294
  app file hashes, all 19 ARM64 Mach-O signatures, bundle signature, plist,
  executable permissions, and the bundled runtime. All 94 shipped upstream
  managed/config files are byte-identical to the attachment.
- The release contains only macOS native runtime assets. The three graphics
  libraries are converted from universal binaries to signed ARM64 slices.
- `git diff --check` passes.

## Live smoke tests

- Launcher 4.0.11.0 opens, loads current news, and reports up to date.
- Fresh upstream settings are isolated with XDG_CONFIG_HOME/XDG_DATA_HOME;
  launcher payloads are isolated with UNORA_LAUNCHER_HOME.
- The native folder picker saves a separate test game directory.
- A fresh game download completes: upstream reports **1,065 files updated**.
- Play starts `Chaos.Client.dll` using the dotnet executable inside the test app
  bundle. Process inspection confirms its test working directory and loaded native
  macOS SDL2 and ARM64 SDL2_mixer libraries. No credentials are entered.
- A simulated newer version directory (`4.0.12.0`, containing the exact 4.0.11.0
  upstream payload) is selected. Restarting with the upstream DLL argument opens
  correctly and uses that directory, including its original universal macOS libraries.

## Evidence limits

The attached archive does not provide managed-source tests or a build project.
Full login/gameplay, saved-character login, macOS 12/13/14/26, Intel hardware,
Apple notarization, and an actual future server-driven launcher update are not
validated. Native game process startup is verified; its login screen and gameplay
were not verified through the UI automation surface.

Normal macOS signature verification accepts the original upstream universal
libraries. Earlier restricted-shell signature errors were reproduced as a sandbox
discrepancy and are not reported as an upstream defect.

Baseline UI inspection allowed the previously installed launcher to perform its
normal cached-payload update. The installed app bundle was not replaced. Subsequent
fresh-install and game-download tests use separate profile and game folders.
