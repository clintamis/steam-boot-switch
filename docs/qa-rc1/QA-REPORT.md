# Steam Boot Switch 1.1.0 RC1 — QA report

**Disposition:** built for release review; not published. Unsigned.
The watcher and launcher were compiled from the included source. The tested
Preview 2 UI is retained. FocusGuard and temporary performance instrumentation
are excluded. MIT license is included for the owner's final release review.

## Automated results

35 settings checks, 35 lifecycle checks and 18 final-installer checks passed,
plus the native engine self-test. Raw results are included under `tests`.

| Check | Result | Scope/evidence |
|---|---|---|
| Native build from complete C# | PASS | .NET Framework C# compiler; engine self-test passed |
| Controller counts, dock exclusion, undock gate, Steam game tracking | PASS | Engine logic self-tests; not physical device-transition acceptance |
| No FocusGuard/foreground-forcing code | PASS | Source inspection; original polling cadence retained |
| Clean app install | PASS | Actual EXE, empty isolated app folder on development PC |
| Recognized Alpha 4.6 perf upgrade | PASS | Archived Alpha binary fixture replaced with rebuilt RC1; exact settings retained |
| RC upgrade and reinstall | PASS | Actual EXE; settings retained byte-for-byte |
| Unknown build, invalid config, unrelated task collision | PASS | Refused before replacement; unknown files/task untouched |
| Native watcher startup | PASS | Main process plus native Puck worker observed |
| Task registration and execution | PASS | Separate QA task registered and explicitly started successfully |
| Installed Apps/uninstaller registration | PASS | Per-user entry created and removed |
| Single Start Menu application | PASS | One entry; seeded duplicate removed during upgrade |
| Uninstall, preserve/export settings | PASS | Both native processes/task removed; exact settings preserved/exported |
| Final uninstall cleanup | PASS | Known settings backups and installer recovery EXE removed; no QA task/process left |
| 13-field schema, UI mapping, validation | PASS | All fields round-trip; mode mappings/dependencies checked |
| Save/apply | PASS | Atomic replacement, conflicts, unknown fields, exact backup, real QA watcher restart |
| UI initialization/layout | PASS | Installed entry self-test; three pages rendered without showing desktop windows |
| Final installed payload | PASS | Every app file hash matched the release payload |
| ZIP integrity and SHA-256 | PASS | See PACKAGE-VERIFICATION.txt and SHA256SUMS.txt |
| Memory vs ~75.65 MB benchmark | PASS | ~53.3–54.2 MiB combined native working set, UI closed |
| CPU consistently at/below 0.03% | FAIL strict ceiling | Samples straddle this approximate target; see below |
| Interactive setup/automatic final Settings display | UNVERIFIED live | Inno launch entry configured; silent tests deliberately suppress windows |
| Fresh Windows PC and actual Windows sign-in | UNVERIFIED | Isolated-folder tests are not a clean-OS or logon test |
| Physical docking, shutdown, undocking, reconnect and game sessions | UNVERIFIED for RC1 | Logic retained; no physical controller operations performed this run |
| Steam focus issue and disconnect-time lag | KNOWN / UNVERIFIED | Focus limitation remains; idle measurements do not rule out transition lag |
| Mixed DPI, multiple displays, other controllers, ARM64 | UNVERIFIED | Preview UI previously tested by user; no new display/hardware matrix run |
| Startup-shortcut fallback on task-denied PC | UNVERIFIED live | Fallback implemented; task creation succeeded on this PC |

## Resource measurements

Three approximately 30-second idle/docked samples of the rebuilt engine, two
native processes, 16 logical processors, settings window closed, QA automatic
Steam actions disabled. Existing production monitor remained running separately;
its CPU/memory was not included in these process measurements.

| Sample | CPU time | One-core usage | Machine-normalized usage | Combined working set |
|---|---:|---:|---:|---:|
| 1 | 156.25 ms | 0.5207% | 0.0325% | 54.20 MiB |
| 2 | 187.50 ms | 0.6247% | 0.0390% | 53.83 MiB |
| 3 | 125.00 ms | 0.4166% | 0.0260% | 53.33 MiB |

Machine usage = CPU milliseconds / elapsed milliseconds / 16 * 100.
CPU is low in absolute terms, but two samples exceed a strict 0.03% ceiling;
there is no claim of a proven no-regression result. The Alpha 4.2 benchmark's
sampling method, hardware, controller state and CPU normalization are not
available for an apples-to-apples comparison. No new optimization was introduced
solely to make this short benchmark pass. Disconnect-time latency, driver/DPC
latency and UI-open memory have not been measured here.

The app payload is approximately 173 KiB; the conventional installer is about
2.1 MiB. Installer/uninstaller overhead is additional to the app payload.

## Test corrections and limits

An initial save/apply assertion ran before the restarted worker was established.
Logs confirmed the restart succeeded; the test now waits two seconds and checks
both processes. The corrected suite and final task launch test passed. An initial
headless Window render was blank; rendering the content produced inspectable
page images. Neither correction changed the UI or engine behavior.

Tests used the final EXE silently with a separate QA AppId, task, folder and
Start Menu group. The main installation was not upgraded or uninstalled.
The QA defaults disable actions affecting Steam windows/controllers. The final
installer's installed payload hashes match its source package payload. No mouse,
keyboard, focus manipulation or application-window takeover was used.

Uninstall removes owned native processes and executable-targeted startup tasks.
It leaves unrelated files and historical development archives in existing
folders alone. An open Settings window must be closed before upgrade/uninstall
to avoid losing unsaved choices. If startup configuration fails after copying,
setup reports failure and retains the previous watcher/config recovery files;
repair by rerunning Setup. Full rollback after arbitrary OS failure is not
claimed.

Before public release: test actual logon, controller transitions and active game
protection on another Windows PC; review unsigned distribution and MIT licensing.
Steam's Big Picture close transition may still take foreground focus. RC1 does
not promise to fix that Steam behavior.
