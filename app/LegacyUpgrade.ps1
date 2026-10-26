# V1.0.0 recognition uses archived source hashes, not filenames alone.
# Hashes normalize CRLF to LF so Git checkout settings do not affect recognition.
function Get-SbsTextHash([string]$Path) {
    if(![IO.File]::Exists($Path)){return ''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $text=[IO.File]::ReadAllText($Path).Replace("`r`n","`n")
        [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-','')
    } finally {$sha.Dispose()}
}
function Test-SbsV1([string]$Folder) {
    (Get-SbsTextHash ($Folder+'\SteamControllerBootMode.ps1')) -eq '1AD1E5E1E2E6DB05862DB21BFCBD20A2AE6D6614BC21EE43DFB73134863B4CF7' -and
    (Get-SbsTextHash ($Folder+'\HiddenLauncher.cs')) -eq 'D1A2F1B465957ABC3E76A24341AA72E300E8D0556BA302A22F4FC26B114BC6A7'
}
function Get-SbsV1Processes([string]$Folder) {
    $launcher=$Folder+'\SteamBootHiddenLauncher-1.0.0.exe'
    $watcher=$Folder+'\SteamControllerBootMode.ps1'
    @(Get-CimInstance Win32_Process -Filter "Name='SteamBootHiddenLauncher-1.0.0.exe' OR Name='powershell.exe'" |
      Where-Object {$_.ExecutablePath -ieq $launcher -or
        ($_.Name -ieq 'powershell.exe' -and $_.CommandLine -and
         $_.CommandLine.IndexOf('-File "'+$watcher+'"',[StringComparison]::OrdinalIgnoreCase) -ge 0)})
}
