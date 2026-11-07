# Optional audit of the original PRO preservation event. Never a prerequisite for live FIRE acceptance.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$HistoricalEvidenceRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root='E:\CRAFT-FIRE'
Import-Module (Join-Path $root 'tests\Acceptance.Common.psm1') -Force
$evidence=Get-AcEvidenceRoot (Join-Path $HistoricalEvidenceRoot 'acceptance-input.json')
$output=Join-Path $evidence 'historical-preservation-receipt.json'
$null=Assert-AcEvidencePath $output
if (Test-Path -LiteralPath $output) { throw 'Historical receipt already exists. Read the preserved receipt.' }
if (-not (Test-Path -LiteralPath 'E:\PASS_AI_PRO' -PathType Container)) {
    throw 'Original PRO source tree is unavailable. Historical audit was not run.'
}
$checks=New-Object 'System.Collections.Generic.List[object]'
$historicalObservation=@()
function Check([string]$Name,[bool]$Ok){$checks.Add([pscustomobject]@{name=$Name;ok=$Ok})}
try{
 $before=Read-AcJson (Join-Path $evidence 'pro-before.json')
 $after=@(Get-ChildItem -LiteralPath 'E:\PASS_AI_PRO' -Recurse -File -Force)
 # A separately approved PRO planning move overlapped this task. Verify its exact
 # eight-document scope and retain the original full-snapshot mismatch evidence.
 $proChangeRoot='D:\PASS_AI\TEST\automated\pass-ai-pro-plans-move-20261023-01a15c2b'
 $proChange=Read-AcJson (Join-Path $proChangeRoot 'closure-summary.json')
 $proChangeVerification=Read-AcJson (Join-Path $proChangeRoot 'verification-final.json')
 $proChangeReview=Read-AcJson (Join-Path $proChangeRoot 'independent-handoff.json')
 $proChangeBaseline=Read-AcJson (Join-Path $proChangeRoot 'baseline.json')
 Check 'external-pro-document-work-has-separate-evidence' ($proChange.status -ceq 'PRODUCT_PLANS_RELOCATED_AND_REVIEWED' -and $proChange.product_code_or_cad_or_install_changed -eq $false -and $proChangeVerification.failed -eq 0 -and $proChangeReview.task_id -ceq 'PRO-PLANS-MOVE-REVIEW-20261023-11' -and $proChangeReview.status -ceq 'complete')
 $changedDocs=@('E:\PASS_AI_PRO\README.md','E:\PASS_AI_PRO\docs\ARCHITECTURE.md','E:\PASS_AI_PRO\docs\INSTALLATION.md')
 $addedPlans=@($proChangeReview.evidence | Where-Object {$_ -match '^E:/PASS_AI_PRO/plans/[^/]+$'} | ForEach-Object {$_.Replace('/','\')})
 $observation=New-Object 'System.Collections.Generic.List[object]'
 foreach($file in $before){
  $current=(Get-FileHash -LiteralPath $file.path -Algorithm SHA256).Hash
  if($file.path -cin $changedDocs){
   $externalOriginal=@($proChangeBaseline | Where-Object path -ceq $file.path)
   Check ('pro-document-change-matches-separate-baseline:'+$file.path) ($externalOriginal.Count -eq 1 -and $externalOriginal[0].sha256 -ceq $file.sha256)
   $observation.Add([pscustomobject]@{path=$file.path;before=$file.sha256;after=$current;classification='EXTERNAL APPROVED DOCUMENT CHANGE'})
  }else{Check ('pro-protected-file-preserved:'+$file.path) ($current -ceq $file.sha256)}
 }
 $extra=@($after|Where-Object {$_.FullName -cnotin $before.path})
 Check 'pro-only-five-separately-moved-plan-files-added' ($extra.Count -eq 5 -and @($extra|Where-Object {$_.FullName -cnotin $addedPlans}).Count -eq 0 -and $after.Count -eq 39)
 foreach($file in $extra){$observation.Add([pscustomobject]@{path=$file.FullName;after=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash;classification='EXTERNAL APPROVED PLAN MOVE'})}
 $historicalObservation=$observation.ToArray()

}catch{$checks.Add([pscustomobject]@{name='historical-audit-error';ok=$false;detail=$_.Exception.Message})}
$failed=@($checks | Where-Object {-not $_.ok}).Count
$json=[ordered]@{result=$(if($failed){'FAIL'}else{'PASS'});scope='OPTIONAL_HISTORICAL_PRO_PRESERVATION';timestamp_utc=[DateTimeOffset]::UtcNow.ToString('o');passed=$checks.Count-$failed;failed=$failed;checks=$checks.ToArray();historical_observation=$historicalObservation;live_fire_acceptance='NOT ASSESSED'} | ConvertTo-Json -Depth 10
$stream=[IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
try {
 $bytes=[Text.Encoding]::UTF8.GetBytes($json+[Environment]::NewLine)
 $stream.Write($bytes,0,$bytes.Length)
}finally{$stream.Dispose()}
$json
if($failed){exit 1};exit 0
