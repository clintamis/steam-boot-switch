$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$res=[System.Windows.Forms.MessageBox]::Show('Remove Steam Boot Switch and its startup task? Steam itself will not be changed.','Steam Boot Switch', [System.Windows.Forms.MessageBoxButtons]::YesNo)
if($res -ne [System.Windows.Forms.DialogResult]::Yes){exit 2}
$log=Join-Path $env:TEMP 'SteamBootMode-uninstall.log'
try {
    & (Join-Path $PSScriptRoot 'Uninstall-Core.ps1') *> $log
    [void][System.Windows.Forms.MessageBox]::Show('Steam Boot Switch uninstall completed.','Steam Boot Switch v1.0.0')
} catch {
    [void][System.Windows.Forms.MessageBox]::Show("Uninstall encountered an error: $($_.Exception.Message)`nDetails: $log",'Steam Boot Switch v1.0.0')
}
