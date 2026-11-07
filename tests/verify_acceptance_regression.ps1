# Negative tests consume copies of LIVE evidence. No product, drawing, or original receipt is modified.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AcceptanceManifest)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root='E:\CRAFT-FIRE'
Import-Module (Join-Path $root 'tests\Acceptance.Common.psm1') -Force
$originalEvidence=Get-AcEvidenceRoot $AcceptanceManifest
$baseline=Read-AcJson $AcceptanceManifest 'regression-live-baseline'
$token=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$runRoot='D:\PASS_AI\TEST\automated\pass-ai-fire-acceptance-regression-'+$token
$null=Assert-AcEvidencePath $runRoot
[void][IO.Directory]::CreateDirectory($runRoot)
$results=New-Object 'System.Collections.Generic.List[object]'
$fixtureBuildRoots=New-Object 'System.Collections.Generic.List[string]'
$caseRoots=New-Object 'System.Collections.Generic.List[string]'
function Copy-RegObject($Value){return ,($Value | ConvertTo-Json -Depth 70 | ConvertFrom-Json)}
function Write-RegJson([string]$Path,$Value){ConvertTo-Json -InputObject $Value -Depth 70 | Set-Content -LiteralPath $Path -Encoding UTF8}
function New-RegCase([string]$Id){
 $dir='D:\PASS_AI\TEST\automated\pass-ai-fire-foundation-regression-'+$token+'-'+$Id
 $null=Assert-AcEvidencePath $dir
 Assert-Ac 'REG-FRESH-CASE' (-not(Test-Path -LiteralPath $dir)) $Id
 [void][IO.Directory]::CreateDirectory($dir)
 $caseRoots.Add($dir)
 foreach($name in @('legacy-cache-before.json','legacy-cache-after.json','harness-summary.json','harness.log')){
  $path=Join-Path $originalEvidence $name;$null=Assert-AcEvidencePath $path
  Copy-Item -LiteralPath $path -Destination (Join-Path $dir $name)
 }
 # Deliberately no pro-before.json or historical task folder in a regression case.
 return [pscustomobject]@{id=$Id;directory=$dir;input=(Join-Path $dir 'acceptance-input.json');manifest=(Copy-RegObject $baseline)}
}
function Set-RegReceipt($Case,[string]$Id,$Value){
 $entry=@($Case.manifest.receipts | Where-Object id -ceq $Id)[0]
 $entry.path=Join-Path $Case.directory ('receipt-'+$Id+'.json')
 Write-RegJson $entry.path $Value
 $entry.sha256=(Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash
}
function Get-RegReceipt($Case,[string]$Id){
 $entry=@($Case.manifest.receipts | Where-Object id -ceq $Id)[0]
 return ,(Get-Content -LiteralPath $entry.path -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Copy-RegBuild($Case,[string]$Id='foundation51',[switch]$OmitSource){
 $test=Get-RegReceipt $Case $Id
 $build=Read-AcJson $test.build_receipt ('regression-copy-build:'+$Id)
 $oldRoot=$build.artifacts_root
 $buildRoot='D:\PASS_AI\TEST\automated\pass-ai-fire-build-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
 $null=Assert-AcEvidencePath $buildRoot
 Assert-Ac 'REG-FRESH-BUILD' (-not(Test-Path -LiteralPath $buildRoot)) $buildRoot
 [void][IO.Directory]::CreateDirectory($buildRoot)
 $fixtureBuildRoots.Add($buildRoot)
 foreach($output in $build.outputs){
  Assert-Ac 'REG-COPY-OUTPUT-SCOPE' ($output.path.StartsWith(($oldRoot+'\'),[StringComparison]::OrdinalIgnoreCase)) $output.path
  $destination=Join-Path $buildRoot $output.path.Substring($oldRoot.Length+1)
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
  Copy-Item -LiteralPath $output.path -Destination $destination
  $output.path=$destination
 }
 $source=Join-Path $buildRoot 'source-manifest.json'
 if(-not $OmitSource){Copy-Item -LiteralPath (Join-Path $oldRoot 'source-manifest.json') -Destination $source}
 if(Test-Path -LiteralPath (Join-Path $oldRoot 'core-tests.log')){Copy-Item -LiteralPath (Join-Path $oldRoot 'core-tests.log') -Destination (Join-Path $buildRoot 'core-tests.log')}
 $build.artifacts_root=$buildRoot
 $buildPath=Join-Path $buildRoot 'build-receipt.json'
 Write-RegJson $buildPath $build
 $test.build_receipt=$buildPath
 if($Id -ceq 'cad'){$test.build_receipt_sha256=(Get-FileHash -LiteralPath $buildPath -Algorithm SHA256).Hash}else{$test.evidence_root=$buildRoot}
 Set-RegReceipt $Case $Id $test
 return [pscustomobject]@{Build=$build;Path=$buildPath;Source=$source;ReceiptId=$Id}
}
function Save-RegBuild($Case,$Copy){
 Write-RegJson $Copy.Path $Copy.Build
 if($Copy.ReceiptId -ceq 'cad'){
  $receipt=Get-RegReceipt $Case 'cad'
  $receipt.build_receipt_sha256=(Get-FileHash -LiteralPath $Copy.Path -Algorithm SHA256).Hash
  Set-RegReceipt $Case 'cad' $receipt
 }
}
function Invoke-RegAcceptance($Case,[string]$InputPath){
 $engine=Join-Path $PSHOME $(if($PSVersionTable.PSVersion.Major -eq 5){'powershell.exe'}else{'pwsh.exe'})
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=$engine
 $info.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $root 'setup\run_tests.ps1')+'" -Suite Acceptance -AcceptanceManifest "'+$InputPath+'"'
 $info.WorkingDirectory=$Case.directory
 $tempPath=Join-Path $Case.directory 'temp'
 [void][IO.Directory]::CreateDirectory($tempPath)
 $info.EnvironmentVariables['TEMP']=$tempPath;$info.EnvironmentVariables['TMP']=$tempPath
 $info.EnvironmentVariables['PSModuleAnalysisCachePath']=Join-Path $Case.directory 'module-analysis-cache'
 $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
 $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
 $process=New-Object Diagnostics.Process;$process.StartInfo=$info
 $timedOut=$false
 try{
  if(-not $process.Start()){throw 'Acceptance child did not start'}
  $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit(180000)){$timedOut=$true;$process.Kill();$process.WaitForExit()}
  $stdout=$outTask.GetAwaiter().GetResult();$stderr=$errTask.GetAwaiter().GetResult()
  [IO.File]::WriteAllText((Join-Path $Case.directory 'acceptance.stdout.log'),$stdout)
  [IO.File]::WriteAllText((Join-Path $Case.directory 'acceptance.stderr.log'),$stderr)
  $parsed=$null;try{$parsed=$stdout | ConvertFrom-Json}catch{}
  return [pscustomobject]@{exit_code=$process.ExitCode;process_stopped=$process.HasExited;timed_out=$timedOut;receipt=$parsed;command=($info.FileName+' '+$info.Arguments)}
 }finally{
  if($process.Id -and -not $process.HasExited){$process.Kill();$process.WaitForExit()}
  $process.Dispose()
 }
}
$cases=New-Object 'System.Collections.Generic.List[object]'
function Add-Case([string]$Id,[string]$Kind,[string]$Expected,[string]$Context='',[string]$Target='foundation51'){
 $cases.Add([pscustomobject]@{id=$Id;kind=$Kind;expected=$Expected;context=$Context;target=$Target})
}
Add-Case 'live-no-historical-pro-input' 'positive' ''
Add-Case 'copied-live-build' 'copied-positive' ''
Add-Case 'ordinary-manifest-name' 'ordinary-path' 'AC-MANIFEST-PATH'
Add-Case 'ordinary-evidence-directory' 'ordinary-directory' 'AC-MANIFEST-PATH'
Add-Case 'empty-source-array-original-defect' 'source-empty' 'AC-SOURCE-EMPTY' 'build:foundation51'
Add-Case 'missing-source-manifest' 'source-absent' 'AC-SOURCE-MISSING-MANIFEST' 'build:foundation51'
Add-Case 'missing-current-source-row' 'source-missing' 'AC-SOURCE-SET' 'build:foundation51'
Add-Case 'unrecorded-current-tracking-input' 'source-tracking-missing' 'AC-SOURCE-SET' 'build:foundation51'
Add-Case 'duplicate-source-row' 'source-duplicate' 'AC-SOURCE-DUPLICATE' 'build:foundation51'
Add-Case 'external-source-row' 'source-external' 'AC-SOURCE-PATH' 'build:foundation51'
Add-Case 'sibling-prefix-source-row' 'source-sibling' 'AC-SOURCE-PATH' 'build:foundation51'
Add-Case 'additional-unknown-source-row' 'source-extra' 'AC-SOURCE-SET' 'build:foundation51'
Add-Case 'noncanonical-source-path' 'source-dotdot' 'AC-SOURCE-PATH' 'build:foundation51'
Add-Case 'changed-source-sha256' 'source-hash' 'AC-SOURCE-HASH' 'build:foundation51'
Add-Case 'invalid-source-sha256' 'source-format' 'AC-SOURCE-FORMAT' 'build:foundation51'
Add-Case 'synthetic-top-level-input' 'input-marker' 'AC-SYNTHETIC' 'acceptance-input'
Add-Case 'test-only-top-level-input' 'input-test-only' 'AC-SYNTHETIC' 'acceptance-input'
foreach($id in @('workspace51','workspace7','foundation51','foundation7','profiles51','profiles7','agents51','agents7','boundary','cad')){
 Add-Case ('synthetic-receipt-'+$id) 'receipt-marker' 'AC-SYNTHETIC' ('receipt:'+$id) $id
}
foreach($id in @('foundation51','foundation7','cad')){Add-Case ('synthetic-build-'+$id) 'build-marker' 'AC-SYNTHETIC' ('build:'+$id) $id}
Add-Case 'synthetic-cad-approval' 'approval-marker' 'AC-SYNTHETIC' 'cad:approval'
Add-Case 'wrong-cad-engine-hash' 'engine-hash' 'AC-CAD-ENGINE'
Add-Case 'nested-synthetic-receipt' 'nested-marker' 'AC-SYNTHETIC' 'receipt:foundation51'
Add-Case 'synthetic-source-row' 'source-marker' 'AC-SYNTHETIC' 'build:foundation51'
Add-Case 'receipt-count-inconsistent' 'receipt-count' 'AC-RECEIPT-COUNTS' 'receipt:profiles51' 'profiles51'
Add-Case 'receipt-empty-checks' 'receipt-empty' 'AC-RECEIPT-COUNTS' 'receipt:profiles51' 'profiles51'
Add-Case 'missing-receipt-kind' 'receipt-missing' 'AC-RECEIPTS'
Add-Case 'duplicate-receipt-kind' 'receipt-duplicate' 'AC-RECEIPTS'
Add-Case 'wrong-shell-version' 'shell' 'AC-SHELL:foundation51'
Add-Case 'missing-build-output' 'output-count' 'AC-BUILD-OUTPUTS' 'build:foundation51'
Add-Case 'wrong-build-version' 'build-version' 'AC-BUILD-SCOPE' 'build:foundation51'
try{
 foreach($definition in $cases){
  $case=New-RegCase $definition.id;$copy=$null
  $kind=$definition.kind
  if($kind -like 'source-*' -or $kind -in @('copied-positive','build-marker','output-count','build-version')){
   $copy=Copy-RegBuild $case $definition.target -OmitSource:($kind -ceq 'source-absent')
  }
  if($kind -like 'source-*' -and $kind -cne 'source-absent'){
   $decodedRows=Get-Content -LiteralPath $copy.Source -Raw -Encoding UTF8 | ConvertFrom-Json
   $rows=@(foreach($row in $decodedRows){$row})
   $selected=@($rows | Where-Object path -ceq 'E:\CRAFT-FIRE\src\Core\Foundation.cs')[0]
   switch($kind){
    'source-empty' {$rows=@()}
    'source-missing' {$rows=@($rows | Where-Object path -cne $selected.path)}
    'source-tracking-missing' {$rows=@($rows | Where-Object path -cne 'E:\CRAFT-FIRE\docs\FIRE_FEATURE_CATALOG.json')}
    'source-duplicate' {$rows+=Copy-RegObject $selected}
    'source-external' {$selected.path='D:\PASS_AI\TEST\external.cs'}
    'source-sibling' {$selected.path='E:\CRAFT-FIRE_OTHER\src\Core\Foundation.cs'}
    'source-extra' {$rows+=[pscustomobject]@{path='E:\CRAFT-FIRE\src\unexpected.cs';sha256=('0'*64)}}
    'source-dotdot' {$selected.path='E:\CRAFT-FIRE\src\Core\..\Core\Foundation.cs'}
    'source-hash' {$selected.sha256=$(if($selected.sha256.StartsWith('0')){'1'}else{'0'})+$selected.sha256.Substring(1)}
    'source-format' {$selected.sha256='not-a-sha256'}
    'source-marker' {$selected | Add-Member -NotePropertyName fixture_scope -NotePropertyValue 'synthetic-source-row'}
   }
   Write-RegJson $copy.Source $rows
  }
  switch($kind){
   'input-marker' {$case.manifest | Add-Member -NotePropertyName fixture_scope -NotePropertyValue 'synthetic-review-only-not-live-evidence'}
   'input-test-only' {$case.manifest | Add-Member -NotePropertyName test_only -NotePropertyValue $true}
   'receipt-marker' {$value=Get-RegReceipt $case $definition.target;$value | Add-Member -NotePropertyName fixture_scope -NotePropertyValue 'synthetic-review-only-not-live-evidence';Set-RegReceipt $case $definition.target $value}
   'approval-marker' {
    $value=Get-RegReceipt $case 'cad'
    $approval=Read-AcJson $value.approval_path 'regression-copy-approval'
    $approval | Add-Member -NotePropertyName fixture_scope -NotePropertyValue 'synthetic-approval'
    $value.approval_path=Join-Path $case.directory 'session-approval.json'
    Write-RegJson $value.approval_path $approval
    $value.approval_sha256=(Get-FileHash -LiteralPath $value.approval_path -Algorithm SHA256).Hash
    Set-RegReceipt $case 'cad' $value
   }
   'engine-hash' {$value=Get-RegReceipt $case 'cad';$value.engine_sha256=$(if($value.engine_sha256.StartsWith('0')){'1'}else{'0'})+$value.engine_sha256.Substring(1);Set-RegReceipt $case 'cad' $value}
   'nested-marker' {$value=Get-RegReceipt $case 'foundation51';$value | Add-Member -NotePropertyName validation -NotePropertyValue ([pscustomobject]@{fixture_scope='synthetic-nested'});Set-RegReceipt $case 'foundation51' $value}
   'build-marker' {$copy.Build | Add-Member -NotePropertyName fixture_scope -NotePropertyValue 'synthetic-subordinate-build';Save-RegBuild $case $copy}
   'receipt-count' {$value=Get-RegReceipt $case 'profiles51';$value.passed=[int]$value.passed+1;Set-RegReceipt $case 'profiles51' $value}
   'receipt-empty' {$value=Get-RegReceipt $case 'profiles51';$value.checks=@();$value.passed=0;Set-RegReceipt $case 'profiles51' $value}
   'receipt-missing' {$case.manifest.receipts=@($case.manifest.receipts | Where-Object id -cne 'boundary')}
   'receipt-duplicate' {$case.manifest.receipts[9]=Copy-RegObject $case.manifest.receipts[0]}
   'shell' {$value=Get-RegReceipt $case 'foundation51';$value.powershell_version='7.0.0';Set-RegReceipt $case 'foundation51' $value}
   'output-count' {$copy.Build.outputs=@($copy.Build.outputs[0],$copy.Build.outputs[1]);Save-RegBuild $case $copy}
   'build-version' {$copy.Build.version='999.0.0';Save-RegBuild $case $copy}
  }
  Write-RegJson $case.input $case.manifest
  $inputPath=if($kind -ceq 'ordinary-path'){Join-Path $case.directory 'ordinary.json'}elseif($kind -ceq 'ordinary-directory'){Join-Path $runRoot 'acceptance-input.json'}else{$case.input}
  if($inputPath -cne $case.input){Write-RegJson $inputPath $case.manifest}
  $actual=Invoke-RegAcceptance $case $inputPath
  $actualId=Get-AcValue $actual.receipt 'failure_id'
  $detail=Get-AcValue $actual.receipt 'failure_detail'
  $ok=($null -ne $actual.receipt -and $actual.process_stopped -and -not $actual.timed_out)
  if($definition.expected -eq ''){
   $ok=$ok -and $actual.exit_code -eq 0 -and $actual.receipt.result -ceq 'PASS' -and $actual.receipt.failed -eq 0 -and $actualId -ceq ''
  }else{
   $ok=$ok -and $actual.exit_code -eq 1 -and $actual.receipt.result -ceq 'FAIL' -and $actualId -ceq $definition.expected
   if($definition.context){$ok=$ok -and $detail.Contains($definition.context)}
  }
  $results.Add([pscustomobject]@{name=$definition.id;ok=$ok;expected_id=$definition.expected;expected_context=$definition.context;actual_id=$actualId;failure_detail=$detail;exit_code=$actual.exit_code;process_stopped=$actual.process_stopped;timed_out=$actual.timed_out;command=$actual.command;evidence_root=$case.directory;manifest_sha256=(Get-FileHash -LiteralPath $case.input -Algorithm SHA256).Hash})
  # A bad baseline must not masquerade as successful negative tests.
  if(-not $ok -and $definition.expected -eq ''){break}
 }
}catch{$results.Add([pscustomobject]@{name='regression-runner-error';ok=$false;detail=$_.Exception.Message})}
$failed=@($results | Where-Object {-not $_.ok}).Count
$complete=$results.Count -eq $cases.Count
$json=[ordered]@{schema_version='1.0.0';suite='AcceptanceRegression';result=$(if($failed -eq 0 -and $complete){'TEST_ONLY_PASS'}else{'TEST_ONLY_FAIL'});fixture_scope='TEST_ONLY_VERIFIER_REGRESSION_NOT_LIVE_ACCEPTANCE';test_only=$true;timestamp_utc=[DateTimeOffset]::UtcNow.ToString('o');powershell_version=$PSVersionTable.PSVersion.ToString();baseline_manifest=$AcceptanceManifest;baseline_sha256=(Get-FileHash -LiteralPath $AcceptanceManifest -Algorithm SHA256).Hash;passed=$results.Count-$failed;failed=$failed;expected_cases=$cases.Count;executed_cases=$results.Count;checks=$results.ToArray();fixture_build_roots=$fixtureBuildRoots.ToArray();case_roots=$caseRoots.ToArray();evidence_root=$runRoot;cad_execution='NOT RUN';product_build='NOT RUN';original_sources_and_receipts='READ ONLY'} | ConvertTo-Json -Depth 15
$json | Set-Content -LiteralPath (Join-Path $runRoot 'regression-receipt.json') -Encoding UTF8
$json
if($failed -or -not $complete){exit 1};exit 0
