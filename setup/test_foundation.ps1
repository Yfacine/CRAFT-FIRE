[CmdletBinding()]
param(
 [ValidateRange(1,3600)][int]$SdkTimeoutSeconds=30,
 [ValidateRange(1,3600)][int]$RestoreTimeoutSeconds=180,
 [ValidateRange(1,3600)][int]$BuildTimeoutSeconds=120,
 [ValidateRange(1,3600)][int]$CoreTimeoutSeconds=60)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Build.Common.psm1') -Force
$buildJson=& (Join-Path $PSScriptRoot 'build.ps1') -SdkTimeoutSeconds $SdkTimeoutSeconds -RestoreTimeoutSeconds $RestoreTimeoutSeconds -BuildTimeoutSeconds $BuildTimeoutSeconds
$buildExit=$LASTEXITCODE
$build=$buildJson | Out-String | ConvertFrom-Json
if($buildExit -ne 0 -or $build.result -cne 'PASS'){$buildJson;exit 1}
$run=Assert-FireBuildRoot $build.artifacts_root
$checks=New-Object 'System.Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Ok){$checks.Add([pscustomobject]@{name=$Name;ok=$Ok})}
$saved=Set-FireBuildEnvironment $run
$coreStage=$null; $safetyPath=Join-Path $run 'process-safety-receipt.json'
try {
 Import-Module (Join-Path $PSScriptRoot 'Process.Common.psm1') -Force
 $coreStage=Invoke-FireOwnedProcess -Executable $build.outputs[2].path -RunRoot $run -Stage 'core-tests' -TimeoutSeconds $CoreTimeoutSeconds
 $log=[IO.File]::ReadAllText($coreStage.log)
 Check 'compiled-net48-core-tests' ($coreStage.result -ceq 'PASS' -and $log -match 'FIRE_TEST_RESULT checks=\d+ failed=0')
 if($coreStage.result -cne 'PASS'){throw 'Core process failed; inspect core-tests-process.json'}
 $safety=& (Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\verify_process_safety.ps1') -RunRoot $run
 Check 'owned-process-safety-regression' ($safety.result -ceq 'TEST_ONLY_PASS' -and $safety.failed -eq 0)
 foreach($entry in @(& (Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\verify_foundation.ps1') -Build $build)){Check $entry.name $entry.ok}
 & (Join-Path $PSScriptRoot 'export_catalog.ps1') -CheckOnly | Set-Content -LiteralPath (Join-Path $run 'catalog-check.log') -Encoding UTF8
 Check 'catalog-source-matches-full-tracking-manifest' $true
}catch{Check ('runner-error:'+$_.Exception.Message) $false}finally{Restore-FireBuildEnvironment $saved}
$failed=@($checks | Where-Object {-not $_.ok}).Count
$receipt=[ordered]@{result=$(if($failed){'FAIL'}else{'PASS'});timestamp_utc=[DateTimeOffset]::UtcNow.ToString('o');suite='Foundation';powershell_version=$PSVersionTable.PSVersion.ToString();passed=$checks.Count-$failed;failed=$failed;checks=$checks.ToArray();build_receipt=(Join-Path $run 'build-receipt.json');evidence_root=$run;cad_execution='NOT RUN';fire_features='NOT IMPLEMENTED'}
$receipt['core_process_receipt']=(Join-Path $run 'core-tests-process.json')
$receipt['process_safety_receipt']=$safetyPath
$json=$receipt | ConvertTo-Json -Depth 9
$json | Set-Content -LiteralPath (Join-Path $run 'test-receipt.json') -Encoding UTF8
$json
if($failed){exit 1};exit 0
