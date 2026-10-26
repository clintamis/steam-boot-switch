param([Parameter(Mandatory=$true)][string]$LegacyFolder)
$ErrorActionPreference='Stop'
$r=Split-Path $PSScriptRoot -Parent
$root=Join-Path $PSScriptRoot 'installed'
$task='SteamBootSwitch_V111_QA'
$lines=New-Object 'System.Collections.Generic.List[string]'
function Check($ok,[string]$label){if(!$ok){throw $label};$lines.Add('PASS '+$label)}
function Run($file,$a){$p=Start-Process $file -ArgumentList $a -WindowStyle Hidden -PassThru;if(!$p.WaitForExit(90000)){throw 'Timed out'};return $p.ExitCode}
try {
    if(Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue){throw 'Finish other QA runs first.'}
    [void][IO.Directory]::CreateDirectory($root)
    foreach($name in @('SteamControllerBootMode.ps1','HiddenLauncher.cs')){[IO.File]::Copy((Join-Path $LegacyFolder $name),(Join-Path $root $name),$true)}
    . ($r+'\app\LegacyUpgrade.ps1')
    Check (Test-SbsV1 $root) 'Published V1 source recognized'
    $cfg=Get-Content -Raw -LiteralPath ($LegacyFolder+'\config.default.json')|ConvertFrom-Json
    $cfg.autoExitOnDisconnect=$false;$cfg.cleanupSteamWindow=$false
    $text=$cfg|ConvertTo-Json
    [IO.File]::WriteAllText($root+'\config.json',$text)
    # Do not execute the historical watcher: its hard-coded folder is the live app.
    # A benign launcher fixture tests lifecycle ownership and graceful stopping.
    $fixture='using System; using System.IO; using System.Threading; class Fixture { static void Main() { string p=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"stop.flag"); while(!File.Exists(p)) Thread.Sleep(100); } }'
    $fixturePath=$root+'\fixture.cs';[IO.File]::WriteAllText($fixturePath,$fixture)
    $oldExe=$root+'\SteamBootHiddenLauncher-1.0.0.exe'
    & ($env:WINDIR+'\Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:winexe ('/out:'+$oldExe) $fixturePath
    if($LASTEXITCODE -ne 0){throw 'Fixture compile failed'}
    [IO.File]::Delete($fixturePath)
    $action=New-ScheduledTaskAction -Execute $oldExe
    Register-ScheduledTask -TaskName $task -Action $action -Force|Out-Null
    $old=Start-Process $oldExe -WindowStyle Hidden -PassThru
    $result=Run ($r+'\dist\SteamBootSwitchSetup-1.1.1.exe') ('/VERYSILENT /SUPPRESSMSGBOXES /SBSTEST=1 /DIR="'+$root+'" /LOG="'+$PSScriptRoot+'\v1-migration.log"')
    Check ($result -eq 0) 'V1 migration installer succeeds'
    Check ($old.HasExited) 'Owned old launcher stopped'
    Check ([IO.File]::ReadAllText($root+'\config.json') -ceq $text) 'Legacy ten-field settings preserved byte-for-byte'
    Check ((Get-ScheduledTask -TaskName $task).Actions.Execute -ieq ($root+'\SteamBootSwitch.exe')) 'Old task replaced by V1.1.1 Steam Boot Switch task'
    Check (![IO.File]::Exists($oldExe) -and ![IO.File]::Exists($root+'\SteamControllerBootMode.ps1')) 'Recognized obsolete runtime retired'
    Check ([IO.File]::Exists($root+'\rc1-backup\SteamControllerBootMode.ps1')) 'Legacy recovery files retained'
    Check ((Run ($root+'\unins000.exe') '/VERYSILENT /SUPPRESSMSGBOXES /SETTINGS=Delete') -eq 0) 'Migrated installation uninstalls'
    Check (!(Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)) 'Migration task cleaned up'
    # Modified historical source must not authorize task replacement.
    foreach($name in @('SteamControllerBootMode.ps1','HiddenLauncher.cs')){[IO.File]::Copy((Join-Path $LegacyFolder $name),(Join-Path $root $name),$true)}
    [IO.File]::AppendAllText($root+'\SteamControllerBootMode.ps1',"`n# modified")
    Check (!(Test-SbsV1 $root)) 'Modified V1 source refused recognition'
    Check ((Run ($r+'\dist\SteamBootSwitchSetup-1.1.1.exe') ('/VERYSILENT /SUPPRESSMSGBOXES /SBSTEST=1 /DIR="'+$root+'"')) -ne 0) 'Modified V1 installation refused before changes'
    foreach($name in @('SteamControllerBootMode.ps1','HiddenLauncher.cs')){[IO.File]::Delete((Join-Path $root $name))}
    [IO.File]::WriteAllLines(($PSScriptRoot+'\migration-results.txt'),$lines)
} catch {$lines.Add('FAIL '+$_);[IO.File]::WriteAllLines(($PSScriptRoot+'\migration-results.txt'),$lines);exit 1}
