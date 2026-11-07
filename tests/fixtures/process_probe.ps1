param([ValidateSet('Exit','Sleep','SpawnSleep','SpawnExit','SpawnWait','SpawnGrace','Host')][string]$Mode='Exit',
 [string]$Marker='', [int]$Code=0, [string]$Value='', [string]$RunRoot='', [int]$LifetimeMilliseconds=0)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
if($Mode -eq 'Host'){
 Import-Module E:\CRAFT-FIRE\setup\Process.Common.psm1 -Force
 [pscustomobject]@{pid=$PID;executable=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName;powershell_version=$PSVersionTable.PSVersion.ToString()}|ConvertTo-Json|Set-Content -LiteralPath ($Marker+'.host.json') -Encoding UTF8
 $childArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$PSCommandPath,'-Mode','SpawnSleep','-Marker',$Marker)
 $null=Invoke-FireOwnedProcess -Executable 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Arguments $childArgs -RunRoot $RunRoot -Stage 'aborted-owner' -TimeoutSeconds 30
 exit 0
}
if($Marker){[IO.File]::WriteAllText($Marker,[string]$PID)}
if($Mode -eq 'Exit'){
 [Console]::Out.WriteLine('OUT:'+ $Value); [Console]::Error.WriteLine('ERR:kept'); exit $Code
}
if($Mode -in @('SpawnSleep','SpawnExit','SpawnWait','SpawnGrace')){
 $start=New-Object Diagnostics.ProcessStartInfo
 $start.FileName='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
 $start.UseShellExecute=$false; $start.CreateNoWindow=$true
 # Fixture paths are generated beneath a canonical D root and contain no quote characters.
 $start.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Mode Sleep -Marker "'+$Marker+'.child"'
 if($Mode -in @('SpawnWait','SpawnGrace')){$start.Arguments+=' -LifetimeMilliseconds 300'}
 $child=[Diagnostics.Process]::Start($start)
 if($Mode -in @('SpawnExit','SpawnGrace')){exit 0}
 if($Mode -eq 'SpawnWait'){if(-not $child.WaitForExit(4000)){exit 9};exit 0}
}
if($LifetimeMilliseconds -gt 0){Start-Sleep -Milliseconds $LifetimeMilliseconds;exit 0}
while($true){Start-Sleep -Milliseconds 100}
