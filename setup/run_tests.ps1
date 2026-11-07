[CmdletBinding()]
param(
 [ValidateSet('Workspace','Foundation','ProcessSafety','Acceptance','AcceptanceRegression','HistoricalPreservation')][string]$Suite='Foundation',
 [string]$AcceptanceManifest='',
 [string]$HistoricalEvidenceRoot='',
 [ValidateRange(1,3600)][int]$SdkTimeoutSeconds=30,
 [ValidateRange(1,3600)][int]$RestoreTimeoutSeconds=180,
 [ValidateRange(1,3600)][int]$BuildTimeoutSeconds=120,
 [ValidateRange(1,3600)][int]$CoreTimeoutSeconds=60
)
if ($Suite -eq 'ProcessSafety') {
    Set-StrictMode -Version 2.0
    $ErrorActionPreference='Stop'
    Import-Module (Join-Path $PSScriptRoot 'Build.Common.psm1') -Force
    $run=Assert-FireBuildRoot ('D:\PASS_AI\TEST\automated\pass-ai-fire-build-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
    [void][IO.Directory]::CreateDirectory($run)
    $saved=Set-FireBuildEnvironment $run
    try {$result=& (Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\verify_process_safety.ps1') -RunRoot $run}
    finally {Restore-FireBuildEnvironment $saved}
    $result | ConvertTo-Json -Depth 10
    if($result.failed){exit 1};exit 0
}
if ($Suite -eq 'AcceptanceRegression') {
    & (Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\verify_acceptance_regression.ps1') -AcceptanceManifest $AcceptanceManifest
    exit $LASTEXITCODE
}
if ($Suite -eq 'HistoricalPreservation') {
    & (Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\verify_historical_preservation.ps1') -HistoricalEvidenceRoot $HistoricalEvidenceRoot
    exit $LASTEXITCODE
}
if ($Suite -eq 'Acceptance') {
    & (Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\verify_acceptance.ps1') -ManifestPath $AcceptanceManifest
    exit $LASTEXITCODE
}
if ($Suite -eq 'Foundation') {
    & (Join-Path $PSScriptRoot 'test_foundation.ps1') -SdkTimeoutSeconds $SdkTimeoutSeconds -RestoreTimeoutSeconds $RestoreTimeoutSeconds -BuildTimeoutSeconds $BuildTimeoutSeconds -CoreTimeoutSeconds $CoreTimeoutSeconds
    exit $LASTEXITCODE
}
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'Workspace.Common.psm1') -Force
Assert-FirePlainPath -Path $sourceRoot
if ($sourceRoot -ine 'E:\CRAFT-FIRE') { throw 'Unexpected workspace root.' }
$stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss')
$runId = 'pass-ai-fire-workspace-' + $stamp + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$runRoot = Assert-FireEvidencePath -Path (Join-Path 'D:\PASS_AI\TEST\automated' $runId)
if (Test-Path -LiteralPath $runRoot) { throw 'Run directory already exists.' }
[void][IO.Directory]::CreateDirectory($runRoot)
$checks = New-Object 'System.Collections.Generic.List[object]'
try {
    $config = Get-Content -LiteralPath (Join-Path $sourceRoot 'orchestration\workspace.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not (Test-FireWorkspaceConfig $config)) { throw 'Workspace configuration failed validation.' }
    foreach ($relative in @('AGENTS.md','README.md','.gitignore','orchestration\workspace.json','src\README.md','docs\FIRE_REFERENCE.md','docs\ARCHITECTURE.md','setup\inspect_environment.ps1','setup\Workspace.Common.psm1','tests\verify_workspace.ps1')) {
        $checks.Add([pscustomobject]@{name=('required-file:'+$relative);ok=(Test-Path -LiteralPath (Join-Path $sourceRoot $relative) -PathType Leaf)})
    }
    $planFiles = @(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'plans') -Filter '*.md' -File)
    $checks.Add([pscustomobject]@{name='plan-gate-and-development-documents-present';ok=($planFiles.Count -ge 3)})
    $nodes = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -Force)
    $reparse = @($nodes | Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0})
    $checks.Add([pscustomobject]@{name='workspace-has-no-reparse-points';ok=($reparse.Count -eq 0)})
    if ($reparse.Count -gt 0) { throw 'Workspace contains a reparse point.' }
    $generated = @($nodes | Where-Object {($_.PSIsContainer -and $_.Name -in @('bin','obj','__pycache__','node_modules','.venv','cache','artifacts')) -or (-not $_.PSIsContainer -and $_.Extension -in @('.dll','.exe','.pyc','.log','.tmp'))})
    $checks.Add([pscustomobject]@{name='source-tree-has-no-generated-output';ok=($generated.Count -eq 0)})
    foreach ($script in @($nodes | Where-Object {-not $_.PSIsContainer -and $_.Extension -in @('.ps1','.psm1')})) {
        $tokens=$null; $parseErrors=$null
        $null=[System.Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$parseErrors)
        $checks.Add([pscustomobject]@{name=('powershell-syntax:'+$script.Name);ok=(@($parseErrors).Count -eq 0)})
    }
    $boundary = Get-Content -LiteralPath 'E:\PASS_AI\orchestration\workspace-boundaries.json' -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries = @($boundary.planning.project_workspaces | Where-Object {$_.id -ceq 'pass-ai-fire'})
    $registered = $entries.Count -eq 1 -and $entries[0].root -ceq $sourceRoot -and $entries[0].planning_root -ceq $config.planning_root -and $entries[0].development_environment_root -ceq 'E:\PASS_AI' -and $entries[0].does_not_authorize_product_implementation -eq $true
    $checks.Add([pscustomobject]@{name='canonical-document-workspace-registration';ok=$registered})
    $checks.Add([pscustomobject]@{name='canonical-planning-root-registration';ok=(@($boundary.planning.control_document_roots) -ccontains $config.planning_root)})
    $risk = Get-Content -LiteralPath 'E:\PASS_AI\orchestration\risk-policy.json' -Raw -Encoding UTF8 | ConvertFrom-Json
    $riskEntries = @($risk.writable_roots | Where-Object {$_.path -ceq $sourceRoot})
    $checks.Add([pscustomobject]@{name='scoped-product-write-boundary';ok=($riskEntries.Count -eq 1 -and $riskEntries[0].scope -ceq 'product' -and $riskEntries[0].gate -ceq 'user-scoped-product-write')})
    $profiles = Get-Content -LiteralPath $config.product_profiles_policy -Raw -Encoding UTF8 | ConvertFrom-Json
    $fireProfiles=@($profiles.profiles | Where-Object {$_.root -ieq $sourceRoot -or $_.id -ceq 'pass_ai_fire'})
    $checks.Add([pscustomobject]@{name='exact-fire-product-profile';ok=($fireProfiles.Count -eq 1 -and $fireProfiles[0].root -ceq $sourceRoot -and $fireProfiles[0].id -ceq 'pass_ai_fire' -and $fireProfiles[0].test_runner -ceq $config.workspace_runner -and $fireProfiles[0].dependency_installation -ceq 'NOT_APPROVED_BY_PROFILE' -and $fireProfiles[0].cad_execution -ceq 'REQUIRES_EXACT_APPROVAL')})
    foreach ($check in @(& (Join-Path $sourceRoot 'tests\verify_workspace.ps1') -Config $config)) { $checks.Add($check) }
    $environment = & (Join-Path $PSScriptRoot 'inspect_environment.ps1')
    $environment | Set-Content -LiteralPath (Join-Path $runRoot 'environment.json') -Encoding UTF8
    $inspection = $environment | ConvertFrom-Json
    $checks.Add([pscustomobject]@{name='environment-inspection-has-no-execution';ok=($inspection.writes_performed -eq $false -and $inspection.cad_load -ceq 'NOT RUN' -and $inspection.product_build -ceq 'NOT RUN')})
} catch {
    $checks.Add([pscustomobject]@{name=('runner-error:'+$_.Exception.Message);ok=$false})
}
$failed = @($checks | Where-Object {-not $_.ok}).Count
$manifest = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force | ForEach-Object {
    [pscustomobject]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runRoot 'input-manifest.json') -Encoding UTF8
$result = [ordered]@{
    schema_version='1.0.0';run_id=$runId;timestamp_utc=[DateTimeOffset]::UtcNow.ToString('o');
    source_root=$sourceRoot;suite=$Suite;powershell_version=$PSVersionTable.PSVersion.ToString();
    result=$(if($failed -eq 0){'PASS'}else{'FAIL'});passed=($checks.Count-$failed);failed=$failed;
    checks=$checks.ToArray();evidence_root=$runRoot;
    product_build='NOT RUN';product_function_tests='NOT RUN';cad_load='NOT RUN';
    installation='NOT RUN';global_boundary_check='NOT RUN; use the shared boundary verifier separately'
}
$json = $result | ConvertTo-Json -Depth 8
$json | Set-Content -LiteralPath (Join-Path $runRoot 'receipt.json') -Encoding UTF8
$json
if ($failed -gt 0) { exit 1 }
exit 0
