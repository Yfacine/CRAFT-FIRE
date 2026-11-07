Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
function Invoke-FireOwnedProcess {
 [CmdletBinding()]
 param(
  [Parameter(Mandatory=$true)][string]$Executable,
  [string[]]$Arguments=@(),
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z0-9-]{0,39}$')][string]$Stage,
  [ValidateRange(1,3600)][int]$TimeoutSeconds=60,
  [ValidateRange(0,10)][int]$DescendantGraceSeconds=2,
  [ValidateRange(1,30)][int]$CleanupSeconds=5,
  [string]$WorkingDirectory='E:\CRAFT-FIRE'
 )
 $full=[IO.Path]::GetFullPath($RunRoot)
 if($full -cne $RunRoot -or $full -cnotmatch '^D:\\PASS_AI\\TEST\\automated\\pass-ai-fire-build-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$'){throw 'Process evidence requires a canonical FIRE build root'}
 foreach($path in @($full,$WorkingDirectory)){
  $node=Get-Item -LiteralPath $path -Force
  if(-not $node.PSIsContainer){throw 'Process paths must be directories'}
  while($null -ne $node){if(($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Reparse process path rejected'}; $node=$node.Parent}
 }
 if($WorkingDirectory -cne 'E:\CRAFT-FIRE'){throw 'Unexpected process working directory'}
 if(-not [IO.Path]::IsPathRooted($Executable)){throw 'Absolute executable path required'}
 foreach($variable in @('TEMP','TMP')){if([Environment]::GetEnvironmentVariable($variable,'Process') -cne (Join-Path $full 'temp')){throw 'Isolated build TEMP/TMP required before process compilation'}}
 $receiptPath=Join-Path $full ($Stage+'-process.json'); $logPath=Join-Path $full ($Stage+'.log')
 if(Test-Path -LiteralPath $logPath){throw 'Stage log already exists'}
 $receipt=[ordered]@{schema_version='1.0.0';result='STARTED';stage=$Stage;executable=$Executable;arguments=$Arguments;timeout_seconds=$TimeoutSeconds;descendant_grace_seconds=$DescendantGraceSeconds;cleanup_seconds=$CleanupSeconds;started_utc=[DateTimeOffset]::UtcNow.ToString('o');log=$logPath;receipt_path=$receiptPath;ownership='atomic-job-list-at-process-creation-and-kill-on-close';streams='merged-stdout-stderr'}
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($receipt|ConvertTo-Json -Depth 6))
 $file=[IO.File]::Open($receiptPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 try{$file.Write($bytes,0,$bytes.Length)}finally{$file.Dispose()}
 try {
  # Bootstrap compilation uses isolated TEMP/TMP but precedes the owned stage deadline/job.
  if(-not ('PassAiFire.Execution.OwnedStage' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'OwnedProcess.cs')}
  $r=[PassAiFire.Execution.OwnedStage]::Run($Executable,$Arguments,$WorkingDirectory,$logPath,$TimeoutSeconds*1000,$DescendantGraceSeconds*1000,$CleanupSeconds*1000)
  $receipt['process']=$r
  $receipt.result=if($r.Failure -eq '' -and $r.JobAssigned -and $r.AtomicJobCreation -and $r.RootExited -and $r.CleanupSucceeded -and $r.ActiveAfter -eq 0 -and $r.ExitCode -eq 0){'PASS'}else{'FAIL'}
 }catch{$receipt.result='FAIL';$receipt['error']=$_.Exception.Message}
 $receipt['finished_utc']=[DateTimeOffset]::UtcNow.ToString('o')
 if(Test-Path -LiteralPath $logPath){
  try{
   $stream=[IO.File]::Open($logPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
   $algorithm=[Security.Cryptography.SHA256]::Create()
   try{$receipt['log_sha256']=[BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$algorithm.Dispose()}
  }catch{$receipt.result='FAIL';$receipt['log_hash_error']=$_.Exception.Message}
 }
 $temporary=$receiptPath+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($temporary,($receipt|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 [IO.File]::Replace($temporary,$receiptPath,($receiptPath+'.started'))
 [pscustomobject]$receipt
}
Export-ModuleMember -Function Invoke-FireOwnedProcess
