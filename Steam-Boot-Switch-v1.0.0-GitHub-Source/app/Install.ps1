$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$log=Join-Path $env:TEMP 'SteamBootSwitch-setup.log'
try {
    # Overwrite the single setup log each time, not a new logfile per update.
    & (Join-Path $PSScriptRoot 'Install-Core.ps1') *> $log
    if ($LASTEXITCODE -eq 2) { exit 2 }
    $folder=Join-Path $env:LOCALAPPDATA 'SteamControllerBootMode'
    $versionFile = Join-Path $folder 'install-version.txt'
    if (!(Test-Path -LiteralPath $versionFile) -or
        ((Get-Content -LiteralPath $versionFile -Raw).Trim() -ne '1.0.0')) {
        throw 'The new version could not be verified; see setup log.'
    }
    [void][System.Windows.Forms.MessageBox]::Show(
        "Steam Boot Switch v1.0.0 is ready.

Your chosen settings have been saved. Big Picture starts automatically only at Windows sign-in when a controller is detected.

This installation will not open Big Picture in your current session.",
        'Steam Boot Switch', [System.Windows.Forms.MessageBoxButtons]::OK)
    exit 0
} catch {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Setup encountered a problem: $($_.Exception.Message)`n`nDetails: $log", 'Steam Boot Switch',
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
