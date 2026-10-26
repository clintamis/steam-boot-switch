param([string]$InnoCompiler='')
$ErrorActionPreference='Stop'
$r=$PSScriptRoot
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(!(Test-Path $csc)){$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'}
$common=@('/nologo','/target:winexe','/optimize+','/platform:anycpu','/warn:4','/reference:System.dll','/reference:System.Core.dll')
& $csc @common ('/out:'+$r+'\app\SteamBootSwitchNative-alpha4.exe') /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll ($r+'\src\Core.cs') ($r+'\src\Win.cs') ($r+'\src\PuckNative.cs') ($r+'\src\Program.cs') ($r+'\src\AssemblyInfo.cs')
if($LASTEXITCODE -ne 0){throw 'Watcher compilation failed.'}
& $csc @common /reference:System.Windows.Forms.dll ('/out:'+$r+'\app\SteamBootSwitchSettings.exe') ('/win32icon:'+$r+'\app\SteamBootSwitch.ico') ($r+'\src\SettingsLauncher.cs') ($r+'\src\AssemblyInfo.cs')
if($LASTEXITCODE -ne 0){throw 'Settings launcher compilation failed.'}
$known=@(
'293E044AC21974955A1A084C456289E5E41DE400FCE66337450DBFE325AE3996',
'B478C51B982DB561CE5D211B2E9319EAA6188D210FA808A8E8C6EFB1AFB3E13E',
'C2241172B22708B5E42874BAB4BF64CF6596E78811651DE2FD085144564A94B0',
'5788E32F8E2985C3ED8400F4F5390826AF8ABA3183E529299EF80F2DB2E90713',
'67F1DBD11F0DF448EECE56DBACB474AC8ACA844F665DCAFDA7895D326BD288A3',
'2DFB90D3BC6549379E7DA032591D6F79A682AAF28E2B497F00B203596D969FB8')
# Each compilation changes the PE timestamp. Preserve recognized RC builds locally.
$list=Join-Path $r 'app\recognized-engines.txt'
if(Test-Path $list){$known+=Get-Content -LiteralPath $list}
$known+=(Get-FileHash -LiteralPath ($r+'\app\SteamBootSwitchNative-alpha4.exe') -Algorithm SHA256).Hash
[IO.File]::WriteAllLines($list,@($known|Sort-Object -Unique))
$p=Start-Process -FilePath ($r+'\app\SteamBootSwitchNative-alpha4.exe') -ArgumentList ('--selftest "'+$r+'\tests\engine-selftest.txt"') -PassThru -WindowStyle Hidden
if(!$p.WaitForExit(30000) -or $p.ExitCode -ne 0){throw 'Engine self-test failed.'}
if(!$InnoCompiler){$InnoCompiler=Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'}
if(!(Test-Path $InnoCompiler)){throw 'Pass -InnoCompiler with the path to Inno Setup 6 ISCC.exe.'}
& $InnoCompiler ($r+'\Setup.iss')
if($LASTEXITCODE -ne 0){throw 'Installer compilation failed.'}
Get-FileHash -LiteralPath ($r+'\dist\SteamBootSwitchSetup-1.1.0.exe') -Algorithm SHA256
