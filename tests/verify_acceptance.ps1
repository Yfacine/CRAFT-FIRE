# Live evidence audit only. No build, CAD launch, installation, or Gate mutation.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ManifestPath)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root='E:\CRAFT-FIRE'
Import-Module (Join-Path $root 'tests\Acceptance.Common.psm1') -Force
$checks=New-Object 'System.Collections.Generic.List[object]'
$evidence='';$outputPath='';$failureId='';$failureDetail=''
function Check([string]$Name,[bool]$Ok){
 $checks.Add([pscustomobject]@{name=$Name;ok=$Ok})
 Assert-Ac $Name $Ok $Name
}
try{
 $evidence=Get-AcEvidenceRoot $ManifestPath
 $candidateOutput=Join-Path $evidence 'acceptance-receipt.json'
 $null=Assert-AcEvidencePath $candidateOutput
 $outputPath=$candidateOutput
 $m=Read-AcJson $ManifestPath 'acceptance-input'
 Check 'AC-INPUT-SCHEMA' ($m.schema_version -ceq '2.0.0' -and $m.product_root -ceq $root -and $m.purpose -ceq 'LIVE_FOUNDATION_ACCEPTANCE')
 $required=@('workspace51','workspace7','foundation51','foundation7','profiles51','profiles7','agents51','agents7','boundary','cad')
 Check 'AC-RECEIPTS' (@($m.receipts).Count -eq $required.Count -and @($m.receipts | Select-Object -ExpandProperty id -Unique).Count -eq $required.Count -and @($required | Where-Object {$_ -cnotin $m.receipts.id}).Count -eq 0)
 $loaded=@{}
 foreach($entry in $m.receipts){
  $value=Read-AcJson $entry.path ('receipt:'+$entry.id)
  Check ('AC-RECEIPT-HASH:'+$entry.id) ($entry.sha256 -cmatch '^[A-Fa-f0-9]{64}$' -and (Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash -ieq $entry.sha256)
  if($entry.id -in @('agents51','agents7')){
   Assert-AcCounts $value ('receipt:'+$entry.id) 'results' -NoResult
   Check ('AC-AGENT-SCOPE:'+$entry.id) ($value.root -ceq 'E:\PASS_AI')
  }elseif($entry.id -ceq 'boundary'){
   Assert-AcCounts $value ('receipt:'+$entry.id) -NoResult
   Check 'AC-BOUNDARY-SCOPE' ($value.schema_version -ceq '1.0.0' -and $value.project_root -ceq 'E:\PASS_AI')
  }else{Assert-AcCounts $value ('receipt:'+$entry.id)}
  Check ('AC-RECEIPT-PASS:'+$entry.id) $true
  $loaded[$entry.id]=$value
 }
 foreach($id in @('workspace51','workspace7')){
  Check ('AC-WORKSPACE-SCOPE:'+$id) ($loaded[$id].source_root -ceq $root -and $loaded[$id].suite -ceq 'Workspace')
 }
 foreach($id in @('workspace51','foundation51','workspace7','foundation7')){
  $pattern=if($id.EndsWith('51')){'^5\.1\.'}else{'^7\.'}
  Check ('AC-SHELL:'+$id) ($loaded[$id].powershell_version -match $pattern)
 }
 foreach($id in @('foundation51','foundation7')){
  $test=$loaded[$id]
  Check ('AC-FOUNDATION-SCOPE:'+$id) ($test.suite -ceq 'Foundation' -and $test.fire_features -ceq 'NOT IMPLEMENTED')
  $build=Read-AcJson $test.build_receipt ('build:'+$id)
  Assert-AcBuild $build $test.build_receipt ('build:'+$id) -RequireCoreLog
  Check ('AC-BUILD-VERIFIED:'+$id) $true
  $loaded['build-'+$id]=$build
 }
 for($i=0;$i -lt 3;$i++){
  Check ('AC-DETERMINISTIC-OUTPUT:'+ $i) ($loaded['build-foundation51'].outputs[$i].sha256 -ieq $loaded['build-foundation7'].outputs[$i].sha256)
 }
 $cad=$loaded.cad
 $cadBuild=Read-AcJson $cad.build_receipt 'build:cad'
 Assert-AcBuild $cadBuild $cad.build_receipt 'build:cad'
 Check 'AC-CAD-BUILD-HASH' ($cad.build_receipt_sha256 -ieq (Get-FileHash -LiteralPath $cad.build_receipt -Algorithm SHA256).Hash)
 Check 'AC-CAD-MODE-OWNED-EXITED' ($cad.mode -ceq 'ACTUAL ISOLATED AUTOCAD2024 CORE CONSOLE' -and $cad.exit_code -eq 0 -and $cad.process_stopped -is [bool] -and $cad.process_stopped -eq $true -and $cad.timed_out -is [bool] -and $cad.timed_out -eq $false -and $cad.owned_pid -gt 0)
 for($i=0;$i -lt 3;$i++){Check ('AC-CAD-SAME-OUTPUT:'+$i) ($cadBuild.outputs[$i].sha256 -ieq $loaded['build-foundation51'].outputs[$i].sha256)}
 $approval=Read-AcJson $cad.approval_path 'cad:approval'
 Check 'AC-CAD-APPROVAL-HASH' ($cad.approval_sha256 -ieq (Get-FileHash -LiteralPath $cad.approval_path -Algorithm SHA256).Hash)
 Check 'AC-CAD-APPROVAL-SCOPE' ($approval.decision -ceq 'APPROVED' -and $approval.product_root -ceq $root -and $approval.scope -ceq 'foundation-registration-build-isolated-cad-diagnostics' -and $approval.host -ceq 'AutoCAD2024' -and ($approval.commands -join ',') -ceq 'PASSAIFIRE_ABOUT,PASSAIFIRE_STATUS')
 foreach($key in @('drawing_edits','global_settings','feature_development')){Check 'AC-CAD-APPROVAL-LIMITS' ($approval.$key -is [bool] -and $approval.$key -eq $false)}
 $expectedEngine='C:\Program Files\Autodesk\AutoCAD 2024\accoreconsole.exe'
 Assert-AcPlainPath $expectedEngine
 Check 'AC-CAD-ENGINE' ($cad.engine -ceq $expectedEngine -and $cad.engine_sha256 -ieq (Get-FileHash -LiteralPath $expectedEngine -Algorithm SHA256).Hash -and (Get-Item -LiteralPath $expectedEngine).VersionInfo.FileVersion -match '^24\.3\.')
 Check 'AC-CAD-TEMPLATE-SCOPE' ($cad.template -ceq 'C:\Users\SYBME_PC\AppData\Local\Autodesk\AutoCAD 2024\R24.3\kor\Template\acadiso.dwt')
 $null=Assert-AcEvidencePath $cad.work_root
 Check 'AC-CAD-WORK-ROOT' ($cad.work_root.StartsWith(($cadBuild.artifacts_root+'\cad-smoke-'),[StringComparison]::OrdinalIgnoreCase))
 foreach($i in @(0,1)){
  $copied=Join-Path (Join-Path $cad.work_root 'plugin') ([IO.Path]::GetFileName($cadBuild.outputs[$i].path))
  $null=Assert-AcEvidencePath $copied
  Check ('AC-CAD-LOADED-COPY:'+$i) ((Get-FileHash -LiteralPath $copied -Algorithm SHA256).Hash -ieq $cadBuild.outputs[$i].sha256)
 }
 $stdoutPath=Join-Path $cad.work_root 'stdout.raw';$stderrPath=Join-Path $cad.work_root 'stderr.raw'
 foreach($path in @($stdoutPath,$stderrPath,$cad.template,(Join-Path $cad.work_root 'foundation-input.dwg'))){Assert-AcPlainPath $path}
 function Decode([byte[]]$Bytes){if(@($Bytes | Where-Object {$_ -eq 0}).Count -gt $Bytes.Length/5){return [Text.Encoding]::Unicode.GetString($Bytes)};return [Text.Encoding]::UTF8.GetString($Bytes)}
 $text=Decode ([IO.File]::ReadAllBytes($stdoutPath));$errorText=Decode ([IO.File]::ReadAllBytes($stderrPath))
 $version=Get-Content -LiteralPath (Join-Path $root 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 Check 'AC-CAD-RAW-OUTPUT' ($text.Contains("PASS_AI_FIRE $($version.version) | AutoCAD2024/net48/x64 | foundation-only") -and $text.Contains('PASS_AI_FIRE_STATUS tracked=76 implemented=0 target=FIRE2025+ features=DISABLED') -and $text -match '(?s)_\.QUIT\s+_Y\s+[^\r\n]*<N> _Y')
 Check 'AC-CAD-TEMPLATE-PRESERVED' ($cad.template_sha256 -cmatch '^[A-Fa-f0-9]{64}$' -and (Get-FileHash -LiteralPath $cad.template -Algorithm SHA256).Hash -ieq $cad.template_sha256 -and (Get-FileHash -LiteralPath (Join-Path $cad.work_root 'foundation-input.dwg') -Algorithm SHA256).Hash -ieq $cad.template_sha256)
 $known="ERROR: Can't delete temp file "+(Join-Path $cad.work_root ('accc'+$cad.owned_pid+'2.'))+' (errno=13).'
 foreach($warning in $cad.warnings){Check 'AC-CAD-KNOWN-WARNING' ($warning -ceq $known)}
 $unclassified=[regex]::Replace(($text+[Environment]::NewLine+$errorText),'(?im)^'+[regex]::Escape($known)+'\s*$','')
 Check 'AC-CAD-NO-RAW-ERRORS' ($unclassified -notmatch '(?im)\bERROR\b|Unknown command|\uC54C \uC218 \uC5C6\uB294 \uBA85\uB839|\uBA85\uB839\uC744 \uC54C \uC218|Unable to load|\uB85C\uB4DC\uD560 \uC218 \uC5C6|Exception|FATAL')
 # Historical adjacent-PRO task checks are exclusively in HistoricalPreservation.
 $cacheBefore=Read-AcJson (Join-Path $evidence 'legacy-cache-before.json') 'cache:before'
 $cacheAfter=Read-AcJson (Join-Path $evidence 'legacy-cache-after.json') 'cache:after'
 foreach($cache in @($cacheBefore,$cacheAfter)){Check 'AC-CACHE-SCHEMA' ($cache.mode -ceq 'product-source-cache-only' -and $cache.cache_file_count -ge 0 -and $cache.cache_directory_count -ge 0 -and $cache.cache_total_bytes -ge 0)}
 $rowsBefore=@($cacheBefore.cache_manifest | ForEach-Object {'{0}|{1}|{2}|{3}' -f $_.path,$_.type,$_.length,$_.sha256} | Sort-Object -CaseSensitive)
 $rowsAfter=@($cacheAfter.cache_manifest | ForEach-Object {'{0}|{1}|{2}|{3}' -f $_.path,$_.type,$_.length,$_.sha256} | Sort-Object -CaseSensitive)
 Check 'AC-LEGACY-CACHE-PRESERVED' ([string]::Join([char]10,[string[]]$rowsBefore) -ceq [string]::Join([char]10,[string[]]$rowsAfter) -and $cacheBefore.cache_file_count -eq $cacheAfter.cache_file_count -and $cacheBefore.cache_directory_count -eq $cacheAfter.cache_directory_count -and $cacheBefore.cache_total_bytes -eq $cacheAfter.cache_total_bytes)
 $harness=Read-AcJson (Join-Path $evidence 'harness-summary.json') 'harness-summary'
 $harnessLog=Join-Path $evidence 'harness.log';$null=Assert-AcEvidencePath $harnessLog
 $summaries=[regex]::Matches([IO.File]::ReadAllText($harnessLog),'Harness validation: ([0-9]+) passed, ([0-9]+) failed, ([0-9]+) warnings')
 Check 'AC-HARNESS-SUMMARY' ($summaries.Count -gt 0)
 $summary=$summaries[$summaries.Count-1]
 Check 'AC-HARNESS-PASS' ($harness.exit_code -eq 0 -and $harness.failed -eq 0 -and $harness.result -ceq 'PASS' -and $harness.passed -gt 0 -and $harness.passed -eq [int]$summary.Groups[1].Value -and $harness.failed -eq [int]$summary.Groups[2].Value -and $harness.warnings -eq [int]$summary.Groups[3].Value -and $harness.log_sha256 -ieq (Get-FileHash -LiteralPath $harnessLog -Algorithm SHA256).Hash)
 $policy=Get-Content -LiteralPath 'E:\PASS_AI\orchestration\product-profiles.json' -Raw -Encoding UTF8 | ConvertFrom-Json
 $fire=@($policy.profiles | Where-Object id -ceq 'pass_ai_fire')
 Check 'AC-PRODUCT-PROFILE' ($fire.Count -eq 1 -and $fire[0].root -ceq $root -and $fire[0].test_runner -ceq (Join-Path $root 'setup\run_tests.ps1') -and $fire[0].dependency_installation -ceq 'NOT_APPROVED_BY_PROFILE' -and $fire[0].cad_execution -ceq 'REQUIRES_EXACT_APPROVAL')
 $cfg=Get-Content -LiteralPath (Join-Path $root 'orchestration\workspace.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 Check 'AC-STOP-BEFORE-FEATURES' (Test-AcWorkspaceConfig $cfg)
 $links=New-Object 'System.Collections.Generic.List[string]'
 foreach($doc in Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.md'){
  foreach($match in [regex]::Matches([IO.File]::ReadAllText($doc.FullName),'\]\(([^)]+)\)')){
   $target=$match.Groups[1].Value.Trim('<','>')
   if($target -match '^(https?://|#|mailto:)' -or $target -match '^<'){continue}
   $target=($target -split '#')[0]
   if($target -and -not(Test-Path -LiteralPath ([IO.Path]::GetFullPath((Join-Path $doc.DirectoryName $target))))){$links.Add($doc.FullName+':'+$target)}
  }
 }
 Check 'AC-MARKDOWN-LINKS' ($links.Count -eq 0)
}catch{
 $failureDetail=$_.Exception.Message
 $match=[regex]::Match($failureDetail,'^\[([A-Za-z0-9:._-]+)\]')
 $failureId=if($match.Success){$match.Groups[1].Value}else{'AC-UNEXPECTED'}
 $checks.Add([pscustomobject]@{name=$failureId;ok=$false;detail=$failureDetail})
}
$failed=@($checks | Where-Object {-not $_.ok}).Count
$result=[ordered]@{schema_version='2.0.0';result=$(if($failed){'FAIL'}else{'PASS'});timestamp_utc=[DateTimeOffset]::UtcNow.ToString('o');scope='LIVE_FOUNDATION_ACCEPTANCE';assessment='deterministic evidence audit; independent review remains a separate Gate';passed=$checks.Count-$failed;failed=$failed;failure_id=$failureId;failure_detail=$failureDetail;checks=$checks.ToArray();manifest_path=$ManifestPath;manifest_sha256=$(if(Test-Path -LiteralPath $ManifestPath -PathType Leaf){(Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash}else{$null})}
$json=$result | ConvertTo-Json -Depth 12
if($outputPath -and (Test-Path -LiteralPath $evidence -PathType Container)){$json | Set-Content -LiteralPath $outputPath -Encoding UTF8}
$json
if($failed){exit 1};exit 0
