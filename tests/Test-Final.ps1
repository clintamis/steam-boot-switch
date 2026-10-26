$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$r=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot 'installed'
$exe=$root+'\SteamBootSwitch.exe'
$lines=New-Object 'System.Collections.Generic.List[string]'
function Check($ok,[string]$label){if(!$ok){throw $label};$lines.Add('PASS '+$label)}
function Instances {@(Get-CimInstance Win32_Process -Filter "Name='SteamBootSwitch.exe'"|Where-Object {$_.ExecutablePath -ieq $exe})}
function Run($file,$a){$p=Start-Process $file -ArgumentList $a -PassThru -WindowStyle Hidden;if(!$p.WaitForExit(90000)){throw 'Timed out'};return $p.ExitCode}
try {
    $setup=$r+'\dist\SteamBootSwitchSetup-1.1.1.exe'
    Check ((Run $setup ('/VERYSILENT /SUPPRESSMSGBOXES /SBSTEST=1 /DIR="'+$root+'" /LOG="'+$PSScriptRoot+'\final-install.log"')) -eq 0) 'Final installer clean install'
    foreach($file in [IO.Directory]::GetFiles($r+'\app')){
        $installed=Join-Path $root ([IO.Path]::GetFileName($file))
        Check ((Get-FileHash $file).Hash -eq (Get-FileHash $installed).Hash) ('Installed bytes match '+[IO.Path]::GetFileName($file))
    }
    $identity=(Get-Item $exe).VersionInfo
    Check ($identity.FileDescription -eq 'Steam Boot Switch' -and $identity.ProductName -eq 'Steam Boot Switch') 'Final watcher Task Manager metadata'
    $icon=[Drawing.Icon]::ExtractAssociatedIcon($exe)
    Check ($null -ne $icon -and $icon.Width -gt 0 -and $icon.Height -gt 0) 'Final watcher Task Manager icon resource'
    Check ((Instances).Count -eq 2) 'Final watcher and worker startup'
    [IO.File]::WriteAllText($root+'\stop.flag','stop')
    for($i=0;$i -lt 60 -and (Instances).Count -ne 0;$i++){Start-Sleep -Milliseconds 400}
    Check ((Instances).Count -eq 0) 'Graceful shutdown before task launch test'
    [IO.File]::Delete($root+'\stop.flag')
    Start-ScheduledTask -TaskName 'SteamBootSwitch_V111_QA'
    Start-Sleep -Seconds 4
    Check ((Instances).Count -eq 2) 'Actual registered task starts watcher and worker'
    Check ((Run ($env:WINDIR+'\System32\WindowsPowerShell\v1.0\powershell.exe') ('-NoProfile -STA -ExecutionPolicy Bypass -File "'+$root+'\Settings.ps1" -SelfTest')) -eq 0) 'Final installed settings UI initialization'
    [IO.File]::WriteAllText($root+'\config.json.before-unified-settings','test backup')
    Check ((Run ($root+'\unins000.exe') '/VERYSILENT /SUPPRESSMSGBOXES /SETTINGS=Export') -eq 0) 'Final uninstaller with export'
    Check (![IO.File]::Exists($root+'\config.json') -and ![IO.File]::Exists($root+'\config.json.before-unified-settings')) 'Export removes live and known backup settings'
    Check ((Instances).Count -eq 0 -and !(Get-ScheduledTask -TaskName 'SteamBootSwitch_V111_QA' -ErrorAction SilentlyContinue)) 'Final cleanup leaves no QA process or task'
    Check (![IO.File]::Exists($root+'\qa-install.marker')) 'QA marker removed'
    [IO.File]::WriteAllLines(($PSScriptRoot+'\final-results.txt'),$lines)
}catch{$lines.Add('FAIL '+$_);[IO.File]::WriteAllLines(($PSScriptRoot+'\final-results.txt'),$lines);exit 1}
