# Changelog

## V1.1.1 - Installer and Task Manager improvements

- Restored a welcome page inside the graphical Windows installer explaining what Steam Boot Switch does.
- Shows the installation location and Start Menu shortcut, with settings-preservation text only for existing configurations.
- Gives the watcher a recognizable Steam Boot Switch name, product description, and embedded app icon in Task Manager.
- Migrates recognized V1.1.0 watcher files and tasks to the new executable name, removes the obsolete image after the new watcher starts, and preserves configuration.
- Controller detection, Puck logic, Big Picture behavior, and settings schema remain unchanged.
- Windows build and automated QA are complete; see QA-REPORT.md for checks and remaining verification limits.
## V1.1.0

- Rebuilt the native C# watcher from complete source; retained isolated Puck
  handling, cached process/state information and reduced stable-dock polling.
- Added optional Steam Controller dock shutdown and configurable undock opening.
- Replaced fullscreen-app assumptions with Steam game-process protection.
- Added the tested Preview 2 settings interface, three sections and all 13 fields.
- Preserved atomic settings writes, validation, unknown values and conflict handling.
- Added a single graphical EXE installer, one Start Menu application and an
  Installed Apps uninstaller with settings preserve/export choices.
- Added verified V1.0.0 source/launcher migration and recognized native/RC1 upgrades.
- Preserved no-activate window hiding and deferred sizing. Steam's focus issue
  remains a known limitation; no FocusGuard included.
- Finalized version labels, complete source packaging, checksums and QA evidence.
- Existing MIT notice retained. Installer unsigned; cross-PC tests incomplete.

## v1.0.0 — First public release

- Promoted the last reboot-tested Beta 10 application behavior to version 1.0.0 without functional changes.
- Documented successful Nintendo Switch 2 controller startup test.
- **Clearly marked Bluetooth controller connections as untested.**
- Updated installer labels, logs, README, and release notes for 1.0.0.
- Retained earlier controller safety checks, five-second default, window cleanup and uninstall/upgrade support.


## v0.8.0-beta.10

- Clarified the project title to advertise automatic Big Picture **entry and exit**.
- Reworded the existing desktop-window cleanup preference as **Console-style** (on) versus **desktop-style** (off). No change to its actual behavior.
- Added a tooltip and README clarification about Steam-managed Home/Guide button presses.
- Documented optional Steam `-silent` startup for a cleaner transition; no Steam startup settings are modified.
- **No changes** to controller detection, polling cadence, Big Picture exit logic, or hidden launcher mechanics.


## v0.8.0-beta.8 — Tested beta candidate

- Fixes the beta.7 PowerShell parsing error in `Install-Core.ps1`.
- Corrects uninstall recognition of versioned hidden launchers.
- Checks installation version before reporting a successful upgrade.
- The development PC successfully completed an in-place upgrade and Windows restart test.
- Documents existing Steam Home-button behavior and outstanding minor limitations.

**No new functional code changes were made for this GitHub-ready packaging refresh.**

## Earlier private betas

- Prototyped controller-aware startup, guarded Big Picture exit, and desktop Steam window hiding.
- Added Steam Controller Puck connection handling, generic wired HID detection, a graphical installer/settings, and reversible setup.
- Fixed a native controller-polling crash by removing the experimental WinMM/XInput path.
- Added an early-logon windowless launcher and rotating diagnostics.

Beta versions prior to `v0.8.0-beta.8` were iterative personal test builds, not public releases.
