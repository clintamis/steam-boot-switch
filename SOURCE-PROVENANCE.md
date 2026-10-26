# V1.1.1 patch provenance

V1.1.1 restores the native Inno Setup welcome page and embeds the application
icon and friendly version metadata into the native watcher. The watcher file
name changes from `SteamBootSwitchNative-alpha4.exe` to `SteamBootSwitch.exe`.
The installer recognizes the prior image, validates its published hash,
stops its process, preserves it in the installer recovery folder, registers
the new image as the scheduled task action, and removes the old image only
after the new monitor starts. Controller monitoring, Puck operations,
actuation logic, and configuration schema are unchanged. Historical V1.1.0
provenance follows.
# V1.1.0 release provenance

V1.1.0 promotes the RC1 baseline below. Engine equivalence is checked in
tests/baseline-results.txt; only release metadata and the isolated QA mutex change.
The Preview 2 interface behavior is preserved. Installer-only additions recognize
the published V1.0.0 source hashes and migrate its launcher/task. Git history and
the existing MIT notice are retained. RC1 acceptance was reported by the owner.

# RC1 component provenance

The old Downloads `native-alpha4-Experimental` source directory was absent.
The development project contained complete Alpha 4.4, 4.5, 4.6, 4.6.1,
4.6.2 and 4.6-perf sources and their development archives.

- Engine: complete `Steam-Boot-Switch-v1.1.0-native-alpha4.6/src`.
  Core.cs, Win.cs and PuckNative.cs are byte-identical to the later perf source.
  The perf Program.cs changes add temporary instrumentation; polling stays
  250/850 ms in the main loop and 1400/2300 ms in the worker.
- Preserved optimizations: short-lived process-name cache, cached controller
  state strings, throttled status formatting, reduced stable-dock polling.
- Preserved fixes: Steam game-process protection instead of treating fullscreen
  applications as games; fail-closed game checks; dock count exclusion;
  one-shot dock shutdown; validated undock gate; startup toggle; no-activate
  window hiding; deferred resizing until the Steam desktop is foreground.
- Excluded: Alpha 4.6.1/4.6.2 focus recovery and accelerated focus polling,
  and the temporary performance logger. Prior experimental binaries are only
  recognized for replacement; none is bundled as the release engine.
- RC1 engine changes: version metadata, configuration/log root alongside the
  executable (same default installed location), separate QA mutex when a QA
  installation marker exists. Detection and actuation logic are preserved.
- UI: Downloads `SteamBootSwitch-v1.1-Preview2-Documentation-Updated`,
  `_app/Settings.ps1`, Settings.Core.ps1, Settings.View.ps1, SettingsLauncher.cs,
  icon and runtime config. Release labels updated; heading punctuation matches
  the request; root resolved beside the launcher. Launcher reports startup
  failures graphically. UI validation, save/merge and restart logic retained.
- README baseline: `SteamBootSwitch-v1.1-README-Edited.txt` in Downloads, the
  cleaned-up user revision. Changelog baseline: documentation-updated archive.
  Only release instructions, current behavior and verification claims changed.
- Installer: new Inno Setup script and hidden maintenance script in this source.

## Recognized historical watcher hashes (SHA-256)

| Version | Hash |
|---|---|
| Alpha 4.4 ChatGPT fix | 293E044AC21974955A1A084C456289E5E41DE400FCE66337450DBFE325AE3996 |
| Alpha 4.5 | 67F1DBD11F0DF448EECE56DBACB474AC8ACA844F665DCAFDA7895D326BD288A3 |
| Alpha 4.6 | 2DFB90D3BC6549379E7DA032591D6F79A682AAF28E2B497F00B203596D969FB8 |
| Alpha 4.6 perf / Preview 2 | B478C51B982DB561CE5D211B2E9319EAA6188D210FA808A8E8C6EFB1AFB3E13E |
| Alpha 4.6.1 focus experiment | C2241172B22708B5E42874BAB4BF64CF6596E78811651DE2FD085144564A94B0 |
| Alpha 4.6.2 focus experiment | 5788E32F8E2985C3ED8400F4F5390826AF8ABA3183E529299EF80F2DB2E90713 |

Unknown builds are refused. Recognition does not imply each historical upgrade
was live-tested; see the QA report. Unrelated files/development archives already
in an installation folder are not recursively deleted by the uninstaller.
