# Steam Boot Switch V1.1.1 — QA report

## Automated results (Windows, 2026-10-26)

| Check | Result | Evidence |
| --- | --- | --- |
| Build from source and installer compile | PASS | .NET Framework C# compilation, watcher self-test, Inno Setup 6.7.3 compile |
| Settings and schema | PASS | 35 checks: all 13 fields round-trip; validation, merge, backup, atomic-save and no-op behavior |
| Install, upgrade, uninstall and reinstall | PASS | 47 checks: clean install, settings/apply, single Start Menu entry, registry, preservation/export and safe refusal cases |
| Upgrade from published V1.1.0 | PASS | Ran downloaded V1.1.0 installer in isolated QA location; preserved `config.json` byte-for-byte, stopped both old processes, replaced old executable and task action, retained one Installed Apps registration |
| V1.0.0 migration | PASS | 11 checks using archived source and benign legacy launcher fixture; preserved ten-field settings and refused modified source |
| Final installer integration | PASS | 21 checks: installed payload hashes, actual scheduled-task startup, settings initialization and uninstall cleanup |
| Watcher Task Manager identity | PASS | New process image `SteamBootSwitch.exe`; Windows file description/product name `Steam Boot Switch`; embedded icon resource present (32×32) |
| Resource sample | PASS, one sample | 30.004 seconds, 0.0293% of 16-core machine capacity, 53.11 MiB combined working set; reference was ~0.03% and ~75.65 MB |
| Source ZIP, checksums and final SHA-256 values | PASS | `Package.ps1` verified all 53 ZIP entries against source and generated installer/source/report hashes |

The lifecycle test first exposed a test-harness-only issue (the icon type was
not loaded in PowerShell); the harness was corrected and rerun. The final runs
reported no failed checks. The published V1.1.0 installer used for migration
matched SHA-256 `C7B0BE2C0EAE1F4692B8A92406B1EECE31FCC15DB1B9653273D59A81A2411ADB`.

## Limits

The welcome page compiled and the installer ran in silent install/upgrade
tests. Its visual layout at 100%, 125%, and 150% DPI and the interactive
welcome-page text were not visually inspected. No mouse or screen control was
used. No physical controller/Puck docking, Bluetooth matrix, cross-PC hardware,
or Big Picture foreground-focus test was run for this patch. The installer is
unsigned. Steam may occasionally take foreground focus when Big Picture
closes; cross-PC and Bluetooth testing remain incomplete.

The historical V1.1.0 report follows. Its measurements and acceptance evidence
are not V1.1.1 test results.

---
# Steam Boot Switch V1.1.0 — QA report

## Baseline and acceptance

V1.1.0 is rebuilt from the tested RC1 native engine and Preview 2 interface.
The owner reported on 2026-10-26 that RC1 passed local Windows acceptance testing.
No detailed new per-controller or cross-PC checklist was supplied; that report
is not presented as independent validation of every hardware combination.
The prior RC1 report and automated results are retained in `docs/qa-rc1/`.

The native engine source is equivalent to RC1 except its version label and
isolated QA mutex name. UI behavior is unchanged; release labels are updated.
Installer additions recognize the published V1.0.0 watcher/launcher source and
migrate its startup task. No experimental FocusGuard code is included.

## Automated verification on the development Windows 11 PC

| Check | Result | Evidence / boundary |
|---|---|---|
| Rebuild watcher and settings launcher from C# | PASS | Build.ps1; no renamed RC1 executable |
| Engine self-test | PASS | tests/engine-selftest.txt |
| Engine equivalence to RC1 | PASS | tests/baseline-results.txt; metadata/QA mutex differences only |
| All 13 settings, validation, atomic writes, conflicts, unknown fields | PASS | 35 checks in tests/settings-results.txt |
| Three settings pages and installed entry initialization | PASS | Headless WPF construction/render; no desktop window takeover |
| Clean app install, RC upgrade, uninstall, reinstall, preserve/export | PASS | tests/lifecycle-results.txt; actual installer in isolated folder |
| RC1 upgrade | PASS | RC1 watcher fixture, exact settings preservation; runtime replaced by V1.1.0 |
| Unknown watcher/config and unrelated task protection | PASS | Refused before replacement in lifecycle tests |
| Published V1.0.0 migration | PASS | tests/migration-results.txt; authentic archived source, benign launcher fixture |
| V1 configuration persistence | PASS | Legacy ten-field JSON preserved byte-for-byte; new defaults applied at read time |
| Native startup/task registration, one Start Menu entry | PASS | Two native processes and QA task; duplicate shortcut cleaned |
| Final exact installer payload/task/uninstall smoke | PASS | tests/final-results.txt; installed file hashes match app/ |
| ZIP entries and SHA-256 | PASS | Package.ps1 verifies decompressed entries; SHA256SUMS.txt accompanies assets |
| MIT notice | PASS | Existing repository LICENSE preserved unchanged |
| Final labels | PASS | Installer/app metadata 1.1.0.0; product labels V1.1.0 |
| Memory vs Alpha 4.2 ~75.65 MB | PASS idle sample | Combined native working set ~53.21 MiB |
| CPU consistently <=0.03% machine capacity | NOT MET | Latest idle sample ~0.0456%; see below |
| RC1 local Windows acceptance | OWNER-REPORTED PASS | User statement; not a new automated physical test |
| Additional PC, Bluetooth, controller/display matrix | UNVERIFIED | No extra hardware coverage claimed |
| Final binary physical sign-in/dock/disconnect/game sessions | NOT RERUN | RC1 behavior retained; automated and migration checks rerun |

## Resource measurements and limitations

The V1.1.0 idle/docked sample measured 218.75 ms CPU over 30.009 seconds, two
native processes, 16 logical processors, Settings closed, QA Steam actions
disabled: 0.7289% of one core or 0.0456% normalized across the machine, with
53.21 MiB combined working set. The production monitor remained running
separately and was not included in those process counters.

RC1's three samples ranged 0.0260–0.0390% machine CPU and 53.33–54.20 MiB.
These short measurements do not demonstrate a consistent <=0.03% ceiling or
an apples-to-apples improvement over the Alpha 4.2 benchmark. That benchmark's
sampling method and environment are unavailable. No disconnect-latency or
DPC/driver-latency measurements were performed during release preparation.

## Migration and test boundaries

The V1.0.0 migration test uses exact historical source for recognition and a
harmless waiting executable named like the old launcher for process ownership
and stop signaling. It does not run the old PowerShell watcher, whose original
hard-coded root would target the live installation. The test exercises settings
preservation, task replacement, retirement, backup, uninstall and rejection of
modified legacy source. This is a migration fixture, not a fresh-PC V1 install.

All installer tests use a separate QA AppId, task, folder and Start Menu group.
Their default settings disable automatic Steam actions. The live installation
was not replaced. Silent tests suppress final Settings display; the interactive
wizard and automatic launch are configured but were not manually retested for
the newly labeled binary. Actual Windows sign-in was not performed.

## Known limitations for the public release

- Steam may occasionally take foreground focus when Big Picture closes.
- The installer is unsigned. Windows may show an unknown-publisher or
  SmartScreen warning; compare SHA-256 checksums before running it.
- Cross-PC hardware compatibility testing is incomplete; Bluetooth is unverified.
- Unknown/non-Steam game detection and very rapid device transitions may differ
  by Steam version, controller, driver and connection type.

This report supports release review; it does not claim universal compatibility,
a fixed Steam focus issue, or a guarantee of no disconnect-time lag.
