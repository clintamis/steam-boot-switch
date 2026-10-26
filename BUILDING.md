# Building Steam Boot Switch 1.1.0

Use Windows 10/11 with .NET Framework 4.8, Windows PowerShell 5.1, and
[Inno Setup 6](https://jrsoftware.org/isdl.php) (tested with 6.7.3).
No NuGet packages or downloaded native watcher binary are required.

From this folder, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -InnoCompiler "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
```

The script compiles the watcher and settings launcher from `src`, runs the
watcher's self-test, and builds `dist\SteamBootSwitchSetup-1.1.0.exe`.
The WPF interface and settings store are the PowerShell source in `app`.
The installer uses `Setup.iss` and `app\Maintenance.ps1`.
The settings process runs only while Settings is open.

This is a reproducible build procedure, not a claim of bit-identical binaries:
the .NET Framework compiler embeds a timestamp/MVID, and Inno embeds build data.
`recognized-engines.txt` records known previous watcher hashes plus builds made
by this script, allowing safe upgrade recognition. The six initial hashes
are documented in SOURCE-PROVENANCE.md. Do not add unverified executables.

## Automated verification

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Settings.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Lifecycle.ps1
```

The settings tests construct and render the UI without showing a window.
Lifecycle tests run the actual installer silently with `/SBSTEST=1`, use
`tests\installed`, a separate `SteamBootSwitch_V110_QA` scheduled task,
a separate Installed Apps registration and a separate QA Start Menu folder.
They exercise actual native processes and HID detection, but disable automatic
Steam actions in the QA defaults. They leave no running QA processes/task.
The production monitor is not stopped. Optional `-LegacyEngine` accepts an
archived, recognized Alpha executable to exercise an Alpha upgrade fixture.
Run only one lifecycle test at a time. A failed test may leave its QA task;
run `tests\installed\unins000.exe /VERYSILENT /SETTINGS=Delete` to clean it up.

Normal setup is per-user, needs no administrator elevation and opens Settings
at completion. Silent setup intentionally suppresses the final UI launch.
Uninstall defaults to retaining settings in silent mode. Explicit options are
`/SETTINGS=Keep`, `/SETTINGS=Export`, and `/SETTINGS=Delete`.

## Release review

Review QA-REPORT.md before publication. The existing repository MIT license is retained. No certificate is
included; the installer is unsigned. For signing, configure Inno Setup's
SignTool using your own certificate; never put a private key in this package.
Inno Setup is a separate build dependency with its own licensing terms; review
those terms if using the build tools commercially. It is not included in the
source ZIP. Steam and Microsoft software are not redistributed by this app.

## Packaging

After testing, run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Package.ps1`.
It creates the complete source ZIP, reads and hashes every ZIP entry, and writes
SHA256SUMS.txt for the installer, source ZIP and QA report. Build outputs are
ignored by Git; the application executables are compiled locally by Build.ps1.

`Test-V1Migration.ps1 -LegacyFolder <folder>` accepts the archived V1.0.0
SteamControllerBootMode.ps1, HiddenLauncher.cs and config.default.json. Obtain
these from the existing V1.0.0 Git tag or its source archive. The test uses the
actual legacy source for recognition, but a benign launcher fixture for process
lifecycle so it never runs the historical watcher against the live installation.
Run `tests\Test-Final.ps1` after building the final installer. Tests must run
sequentially because they share one isolated QA task and folder.