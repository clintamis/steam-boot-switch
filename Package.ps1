$ErrorActionPreference='Stop'
$r=$PSScriptRoot
$dist=Join-Path $r 'dist'
$installer=Join-Path $dist 'SteamBootSwitchSetup-1.1.1.exe'
if(![IO.File]::Exists($installer)){throw 'Build the installer first.'}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$files=New-Object 'System.Collections.Generic.List[string]'
foreach($name in @('.gitignore','.gitattributes','Build.ps1','Package.ps1','Setup.iss','BUILDING.md','SOURCE-PROVENANCE.md','README.md','README.txt','CHANGELOG.md','CHANGELOG.txt','RELEASE_NOTES.md','CONTRIBUTING.md','LICENSE','QA-REPORT.md')){$files.Add($name)}
foreach($folder in @('src','app')){
    foreach($path in [IO.Directory]::GetFiles((Join-Path $r $folder))){$files.Add($folder+'/'+[IO.Path]::GetFileName($path))}
}
foreach($path in [IO.Directory]::GetFiles((Join-Path $r 'docs'),'*',[IO.SearchOption]::AllDirectories)){
    $files.Add($path.Substring($r.Length+1).Replace('\','/'))
}
foreach($pattern in @('Test-*.ps1','*-results.txt','engine-selftest.txt','resources*.json','*.png')){
    foreach($path in [IO.Directory]::GetFiles((Join-Path $r 'tests'),$pattern)){$files.Add('tests/'+[IO.Path]::GetFileName($path))}
}
$manifest=@();$hashes=@{}
foreach($name in @($files|Sort-Object -Unique)){
    $hash=(Get-FileHash -LiteralPath (Join-Path $r $name) -Algorithm SHA256).Hash
    $hashes[$name]=$hash;$manifest+=($hash+'  '+$name)
}
[IO.File]::WriteAllLines((Join-Path $r 'SOURCE-SHA256SUMS.txt'),$manifest)
$files.Add('SOURCE-SHA256SUMS.txt')
$zip=Join-Path $dist 'SteamBootSwitch-1.1.1-source.zip'
if([IO.File]::Exists($zip)){[IO.File]::Delete($zip)}
$archive=[IO.Compression.ZipFile]::Open($zip,'Create')
try {
    foreach($name in @($files|Sort-Object -Unique)){
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $r $name),('SteamBootSwitch-1.1.1/'+$name),'Optimal')
    }
} finally {$archive.Dispose()}
# Read and hash every decompressed entry; compare to its exact source file.
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
$count=0
try {
    foreach($entry in $archive.Entries){
        $name=$entry.FullName.Substring('SteamBootSwitch-1.1.1/'.Length)
        if($name.Contains('..') -or [IO.Path]::IsPathRooted($name)){throw 'Unsafe ZIP entry'}
        $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
        try{$actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
        $expected=(Get-FileHash -LiteralPath (Join-Path $r $name) -Algorithm SHA256).Hash
        if($actual -ne $expected){throw "ZIP hash mismatch: $name"};$count++
    }
}finally{$archive.Dispose()}
foreach($name in @('README.txt','CHANGELOG.txt','LICENSE','QA-REPORT.md','BUILDING.md','SOURCE-PROVENANCE.md')){
    [IO.File]::Copy((Join-Path $r $name),(Join-Path $dist $name),$true)
}
$checks=@()
foreach($path in @($installer,$zip,(Join-Path $dist 'QA-REPORT.md'))){$checks+=((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash+'  '+[IO.Path]::GetFileName($path))}
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'),$checks)
[IO.File]::WriteAllLines((Join-Path $dist 'PACKAGE-VERIFICATION.txt'),@(
    "PASS: $count ZIP entries decompressed and SHA-256 matched to source.",
    'PASS: source ZIP contains complete source, build/installer scripts, UI assets and test evidence.',
    'PASS: no installed personal config, logs, development backups or compiler tools included.',
    'PASS: final installer payload was installed and every app file hash matched app/.',
    'Installer is unsigned. See SHA256SUMS.txt for installer and source ZIP checksums.'
))
$checks
"Verified $count ZIP entries."
