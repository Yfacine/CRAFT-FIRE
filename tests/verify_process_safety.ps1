[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$RunRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'setup\Process.Common.psm1') -Force
$shell=[Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$probe=Join-Path $PSScriptRoot 'fixtures\process_probe.ps1'
$base=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$probe)
$checks=New-Object 'System.Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Ok){$checks.Add([pscustomobject]@{name=$Name;ok=$Ok})}
function Run([string]$Name,[string[]]$Extra,[int]$Seconds=5){Invoke-FireOwnedProcess -Executable $shell -Arguments ($base+$Extra) -RunRoot $RunRoot -Stage ('safety-'+$Name) -TimeoutSeconds $Seconds -DescendantGraceSeconds 1}
function Wait-Marker([string]$Path){$timer=[Diagnostics.Stopwatch]::StartNew();while(-not (Test-Path -LiteralPath $Path) -and $timer.ElapsedMilliseconds -lt 8000){Start-Sleep -Milliseconds 30};if(-not (Test-Path -LiteralPath $Path)){throw ('Missing process marker: '+$Path)}}
function Dead([string]$Path){
 if(-not (Test-Path -LiteralPath $Path)){return $false}
 $number=[int][IO.File]::ReadAllText($Path);$process=Get-Process -Id $number -ErrorAction SilentlyContinue
 if($null -eq $process){return $true};$exited=$process.WaitForExit(5000);$process.Dispose();return $exited
}
$unrelated=$null; $hostProcess=$null; $hostObservation=$null
try {
 $unicode='space '+[char]0xd55c+[char]0xae00+' "quote" end\'
 $r=Run 'normal' @('-Mode','Exit','-Value',$unicode)
 $log=[IO.File]::ReadAllText($r.log)
 Check 'normal-exit-and-argument-quoting' ($r.result -ceq 'PASS' -and $log.Contains('OUT:'+$unicode))
 Check 'stdout-and-stderr-preserved' ($log.Contains('OUT:') -and $log.Contains('ERR:kept') -and $r.log_sha256 -ceq (Get-FileHash -LiteralPath $r.log -Algorithm SHA256).Hash)
 Check 'normal-job-empty-and-root-exited' ($r.process.JobAssigned -and $r.process.RootExited -and $r.process.CleanupSucceeded -and $r.process.ActiveAfter -eq 0)
 Check 'job-assigned-atomically-at-process-creation' $r.process.AtomicJobCreation
 $r=Run 'nonzero' @('-Mode','Exit','-Code','7')
 Check 'nonzero-remains-failure-with-log' ($r.result -ceq 'FAIL' -and $r.process.ExitCode -eq 7 -and $r.process.Failure -ceq 'EXIT_CODE_7' -and [IO.File]::ReadAllText($r.log).Contains('ERR:kept'))
 $r=Run 'timeout' @('-Mode','Sleep') 1
 Check 'timeout-is-failure-and-bounded' ($r.result -ceq 'FAIL' -and $r.process.TimedOut -and $r.process.ElapsedMilliseconds -lt 8000)
 Check 'timeout-owned-root-terminated' ($r.process.CleanupRequested -and $r.process.RootExited -and $r.process.CleanupSucceeded -and $r.process.ActiveAfter -eq 0)
 $marker=Join-Path $RunRoot 'tree-pid.txt'
 $r=Run 'tree' @('-Mode','SpawnSleep','-Marker',$marker) 3
 Check 'timeout-terminates-root-and-child' ($r.process.TimedOut -and $r.process.CleanupSucceeded -and (Dead $marker) -and (Dead ($marker+'.child')))
 $marker=Join-Path $RunRoot 'orphan-pid.txt'
 $r=Run 'orphan' @('-Mode','SpawnExit','-Marker',$marker)
 Check 'root-exit-with-descendant-fails-and-cleans' ($r.result -ceq 'FAIL' -and $r.process.Failure -ceq 'DESCENDANTS_REMAINED' -and $r.process.CleanupRequested -and $r.process.CleanupSucceeded -and (Dead ($marker+'.child')))
 $marker=Join-Path $RunRoot 'joined-pid.txt'
 $r=Run 'joined' @('-Mode','SpawnWait','-Marker',$marker)
 Check 'root-and-descendant-normal-completion' ($r.result -ceq 'PASS' -and $r.process.ActiveAfter -eq 0)
 $marker=Join-Path $RunRoot 'grace-pid.txt'
 $r=Run 'grace' @('-Mode','SpawnGrace','-Marker',$marker)
 Check 'child-natural-exit-within-grace-is-pass-without-kill' ($r.result -ceq 'PASS' -and -not $r.process.CleanupRequested -and $r.process.ActiveAfter -eq 0 -and (Dead ($marker+'.child')))
 $marker=Join-Path $RunRoot 'unrelated-pid.txt'
 $start=New-Object Diagnostics.ProcessStartInfo; $start.FileName=$shell; $start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$probe+'" -Mode Sleep -Marker "'+$marker+'"'
 $unrelated=[Diagnostics.Process]::Start($start); Wait-Marker $marker
 $r=Run 'preserve' @('-Mode','Sleep') 1
 Check 'unrelated-same-executable-survives-owned-kill' ($r.process.CleanupSucceeded -and -not $unrelated.HasExited)
 $hash=(Get-FileHash -LiteralPath $r.receipt_path -Algorithm SHA256).Hash; $rejected=$false
 try{$null=Run 'preserve' @('-Mode','Exit')}catch{$rejected=$true}
 Check 'duplicate-stage-rejected-without-evidence-overwrite' ($rejected -and $hash -ceq (Get-FileHash -LiteralPath $r.receipt_path -Algorithm SHA256).Hash)
 $r=Invoke-FireOwnedProcess -Executable (Join-Path $RunRoot 'missing.exe') -RunRoot $RunRoot -Stage 'safety-missing' -TimeoutSeconds 1
 Check 'launch-failure-no-started-process-or-pass' ($r.result -ceq 'FAIL' -and $r.process.RootPid -eq 0 -and $r.process.CleanupSucceeded)
 $rejected=$false;try{$null=Invoke-FireOwnedProcess -Executable $shell -RunRoot 'E:\CRAFT-FIRE' -Stage 'safety-outside'}catch{$rejected=$true}
 Check 'source-evidence-root-rejected-before-write' ($rejected -and -not (Test-Path E:\CRAFT-FIRE\safety-outside-process.json))
 $marker=Join-Path $RunRoot 'aborted-pid.txt'
 $start.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$probe+'" -Mode Host -Marker "'+$marker+'" -RunRoot "'+$RunRoot+'"'
 $hostProcess=[Diagnostics.Process]::Start($start); Wait-Marker ($marker+'.child')
 $hostObservation=Get-Content -LiteralPath ($marker+'.host.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $hostProcess.Kill(); $hostExited=$hostProcess.WaitForExit(5000)
 Check 'abrupt-owner-host-close-kills-owned-tree' ($hostExited -and $hostObservation.pid -eq $hostProcess.Id -and $hostObservation.executable -ceq $shell -and $hostObservation.powershell_version -ceq $PSVersionTable.PSVersion.ToString() -and (Dead $marker) -and (Dead ($marker+'.child')))
 $started=Get-Content -LiteralPath (Join-Path $RunRoot 'aborted-owner-process.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 Check 'abrupt-host-receipt-never-becomes-pass' ($started.result -ceq 'STARTED')
 Check 'unrelated-process-also-survives-owner-host-abort' (-not $unrelated.HasExited)
}catch{Check ('test-error:'+$_.Exception.Message) $false}
finally{
 foreach($owned in @($hostProcess,$unrelated)){
  if($null -ne $owned){if(-not $owned.HasExited){$owned.Kill();Check 'test-owned-helper-stopped' ($owned.WaitForExit(5000))};$owned.Dispose()}
 }
}
$failed=@($checks|Where-Object {-not $_.ok}).Count
$result=[ordered]@{result=$(if($failed){'TEST_ONLY_FAIL'}else{'TEST_ONLY_PASS'});test_only=$true;suite='ProcessSafety';powershell_version=$PSVersionTable.PSVersion.ToString();timestamp_utc=[DateTimeOffset]::UtcNow.ToString('o');evidence_root=$RunRoot;passed=$checks.Count-$failed;failed=$failed;checks=$checks.ToArray()}
$result['probe_executable']=$shell
$result['aborted_owner']=$hostObservation
$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $RunRoot 'process-safety-receipt.json') -Encoding UTF8
[pscustomobject]$result
