# Changelog

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
