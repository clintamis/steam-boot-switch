Option Explicit
Dim sh, fs, base, command, q
Set sh = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
base = fs.GetParentFolderName(WScript.ScriptFullName)
q = Chr(34)
command = q & sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe" & q & " -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " & q & base & "\app\Uninstall.ps1" & q
sh.Run command, 0, True
