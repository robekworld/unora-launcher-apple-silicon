RWX'S REALLY COOL UNORA LAUNCHER FOR MAC
========================================

System requirements
-------------------
- Apple Silicon Mac (M1 or newer)
- macOS 12 Monterey or newer

Install
-------
1. unzip the download
2. drag “Unora Launcher” to Applications
3. on first launch, control-click the app, choose Open, then choose Open again

the extra first-launch step is required because this locally built app is
ad-hoc signed rather than distributed through Apple notarization or whatever

What's included
----------------
- The supplied Chaos/Unora Launcher 4.0.3.0 client
- native macOS app host and app icon
- the official Microsoft .NET 10.0.10 Apple Silicon runtime
- repaired Apple Silicon Avalonia/Skia native libraries

the app is self-contained; a separate .NET installation is not required.
the writable launcher files and future launcher updates are kept in:

  ~/Library/Application Support/Unora Launcher

IMPORTANTTTTTT compatibility note
----------------------------
the downloaded game client includes native Apple Silicon support and launches
through the .NET runtime bundled with this app. Wine, CrossOver, Whisky, and
Parallels are not required. Steam shortcut integration remains unavailable on
macOS.

Runtime source: https://dotnet.microsoft.com/download/dotnet/10.0

-love rwx
