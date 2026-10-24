# Contributing

This is a first-time vibe-coded project, created with AI assistance and validated so far on only one Windows PC. If you find a problem, thank you for taking the time to report it.

Please open a GitHub issue with the Windows version, controller and connection type, relevant settings, exact reproduction steps, and what you expected. If submitting logs, remove account names, file paths, unrelated window titles, and other private information first.

Changes that affect automatic exit should fail safe: **unknown controller or game state must never be treated as permission to exit Big Picture**. Keep all startup automation opt-in and preserve a working uninstaller.

Pull requests are welcome, but please describe how you tested on real Windows hardware. A successful syntax check is not a substitute for a restart and controller disconnect test.
