[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$EvidenceRoot,
 [int]$HarnessExitCode=-1,
 [string]$Foundation51='',
 [string]$Foundation7='',
 [string]$CadReceipt='',
 [switch]$RefreshManifestsOnly
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'Workspace.Common.psm1') -Force
Import-Module (Join-Path $root 'tests\Acceptance.Common.psm1') -Force
$manifestPath=Join-Path $EvidenceRoot 'acceptance-input.json'
$canonicalRoot=Get-AcEvidenceRoot $manifestPath
Assert-Ac 'AC-COLLECT-ROOT' ($canonicalRoot -ceq $EvidenceRoot -and (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) 'Existing dedicated foundation evidence directory required'
foreach($name in @('harness-summary.json','legacy-cache-after.json','acceptance-input.json','fire-after-manifest.json','changed-files.json')){
 $null=Assert-AcEvidencePath (Join-Path $EvidenceRoot $name)
}
if(-not $RefreshManifestsOnly){
 foreach($path in @($Foundation51,$Foundation7,$CadReceipt)){Assert-Ac 'AC-COLLECT-INPUT' (-not [string]::IsNullOrWhiteSpace($path)) 'Current foundation and CAD receipts required'}
 $logPath=Join-Path $EvidenceRoot 'harness.log'
 $null=Assert-AcEvidencePath $logPath
 $text=[IO.File]::ReadAllText($logPath)
 $matches=[regex]::Matches($text,'Harness validation: ([0-9]+) passed, ([0-9]+) failed, ([0-9]+) warnings')
 Assert-Ac 'AC-COLLECT-HARNESS' ($matches.Count -gt 0 -and $HarnessExitCode -eq 0) 'Actual successful terminal summary required'
 $summary=$matches[$matches.Count-1];$failed=[int]$summary.Groups[2].Value
 Assert-Ac 'AC-COLLECT-HARNESS' ($failed -eq 0 -and [int]$summary.Groups[1].Value -gt 0) 'Harness failed'
 [ordered]@{result='PASS';exit_code=$HarnessExitCode;passed=[int]$summary.Groups[1].Value;failed=$failed;warnings=[int]$summary.Groups[3].Value;log_sha256=(Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash;timestamp_utc=[DateTimeOffset]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'harness-summary.json') -Encoding UTF8
 & 'E:\PASS_AI\scripts\measure_product_source_cache.ps1' -AsJson | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'legacy-cache-after.json') -Encoding UTF8
 $cache=Read-AcJson (Join-Path $EvidenceRoot 'legacy-cache-after.json') 'cache:after'
 Assert-Ac 'AC-COLLECT-CACHE' ($cache.mode -ceq 'product-source-cache-only' -and $cache.cache_file_count -ge 0) 'Invalid source cache receipt'
 $receipts=@(
  [pscustomobject]@{id='workspace51';path=(Join-Path $EvidenceRoot 'workspace-ps51.json')},
  [pscustomobject]@{id='workspace7';path=(Join-Path $EvidenceRoot 'workspace-ps7.json')},
  [pscustomobject]@{id='foundation51';path=$Foundation51},
  [pscustomobject]@{id='foundation7';path=$Foundation7},
  [pscustomobject]@{id='profiles51';path=(Join-Path $EvidenceRoot 'profiles-ps51.json')},
  [pscustomobject]@{id='profiles7';path=(Join-Path $EvidenceRoot 'profiles-ps7.json')},
  [pscustomobject]@{id='agents51';path=(Join-Path $EvidenceRoot 'agent-contract-ps51.json')},
  [pscustomobject]@{id='agents7';path=(Join-Path $EvidenceRoot 'agent-contract-ps7-clean.json')},
  [pscustomobject]@{id='boundary';path=(Join-Path $EvidenceRoot 'boundary-after.json')},
  [pscustomobject]@{id='cad';path=$CadReceipt}
 )
 $pinned=@(foreach($entry in $receipts){
  $value=Read-AcJson $entry.path ('collect:'+$entry.id)
  if($entry.id -in @('foundation51','foundation7','cad')){
   $build=Read-AcJson $value.build_receipt ('collect:build:'+$entry.id)
   Assert-AcBuild $build $value.build_receipt ('collect:build:'+$entry.id) -RequireCoreLog:($entry.id -ne 'cad')
  }
  [pscustomobject]@{id=$entry.id;path=$entry.path;sha256=(Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash}
 })
 [ordered]@{schema_version='2.0.0';product_root=$root;purpose='LIVE_FOUNDATION_ACCEPTANCE';receipts=$pinned;timestamp_utc=[DateTimeOffset]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}
$before=Read-AcJson (Join-Path $EvidenceRoot 'before-manifest.json') 'before-manifest'
$files=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {$_.FullName -notmatch '\\.git\\'} | ForEach-Object {[pscustomobject]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
ConvertTo-Json -InputObject $files -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'fire-after-manifest.json') -Encoding UTF8
$changes=New-Object 'System.Collections.Generic.List[object]'
foreach($file in $files){
 $original=@($before | Where-Object path -ceq $file.path)
 if($original.Count -eq 0 -or $original[0].sha256 -ine $file.sha256){$changes.Add([pscustomobject]@{path=$file.path;kind=$(if($original.Count){'MODIFIED'}else{'ADDED'});sha256=$file.sha256})}
}
foreach($original in $before){
 if($original.path.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -and $original.path -cnotin $files.path){$changes.Add([pscustomobject]@{path=$original.path;kind='DELETED';sha256=$null})}
 elseif($original.path.StartsWith('E:\PASS_AI\',[StringComparison]::OrdinalIgnoreCase)){
  if(-not(Test-Path -LiteralPath $original.path -PathType Leaf)){$changes.Add([pscustomobject]@{path=$original.path;kind='DELETED';sha256=$null})}
  else{$hash=(Get-FileHash -LiteralPath $original.path -Algorithm SHA256).Hash;if($hash -ine $original.sha256){$changes.Add([pscustomobject]@{path=$original.path;kind='MODIFIED';sha256=$hash})}}
 }
}
ConvertTo-Json -InputObject @($changes.ToArray()) -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'changed-files.json') -Encoding UTF8
[pscustomobject]@{result='COLLECTED';harness_exit_code=$HarnessExitCode;manifest=$manifestPath;input_schema_version='2.0.0';changed_files=$changes.Count;acceptance='NOT RUN; run the Acceptance suite separately'} | ConvertTo-Json
