# Invoked only by the workspace runner. No CAD, compiler, network or product execution.
param([Parameter(Mandatory=$true)]$Config)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$results = New-Object 'System.Collections.Generic.List[object]'
$results.Add([pscustomobject]@{name='valid-workspace-accepted';ok=(Test-FireWorkspaceConfig $Config)})
$cases = @(
    @{name='protected-product-root-rejected';key='workspace_root';value='E:\CRAFT-DreamPlus'},
    @{name='retired-workspace-root-rejected';key='workspace_root';value='E:\PASS_AI_FIRE'},
    @{name='workspace-dot-dot-rejected';key='workspace_root';value='E:\CRAFT-FIRE\..\CRAFT-FIRE'},
    @{name='unexpected-preservation-root-rejected';key='protected_product_roots';value=@('E:\CRAFT-DreamPlus','E:\PASS_AI\exe','E:\PASS_AI-FLY')},
    @{name='sibling-prefix-root-rejected';key='workspace_root';value='E:\CRAFT-FIRE_other'},
    @{name='source-tree-evidence-rejected';key='execution_root';value='E:\CRAFT-FIRE\cache'},
    @{name='relative-plan-root-rejected';key='planning_root';value='..\plans'},
    @{name='cross-product-tests-rejected';key='test_source_root';value='E:\CRAFT-DreamPlus\tests'},
    @{name='legacy-runner-rejected';key='workspace_runner';value='E:\PASS_AI\exe\setup\run_tests.ps1'},
    @{name='implicit-installation-rejected';key='dependency_installation_approved';value=$true},
    @{name='implicit-cad-execution-rejected';key='cad_execution_approved';value=$true},
    @{name='implicit-product-implementation-rejected';key='product_implementation_enabled';value=$true},
    @{name='string-approval-flag-rejected';key='cad_execution_approved';value='false'},
    @{name='missing-preservation-root-rejected';key='protected_product_roots';value=@('E:\CRAFT-DreamPlus','E:\PASS_AI\exe')},
    @{name='duplicate-preservation-root-rejected';key='protected_product_roots';value=@('E:\CRAFT-DreamPlus','E:\CRAFT-DreamPlus','E:\PASS_AI\exe')}
)
foreach ($case in $cases) {
    $candidate = $Config | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $candidate.($case.key) = $case.value
    $results.Add([pscustomobject]@{name=$case.name;ok=(-not (Test-FireWorkspaceConfig $candidate))})
}
foreach ($path in @(
    'D:\PASS_AI\TEST_OTHER\automated\pass-ai-fire-workspace-20261022-100000-aaaaaaaa',
    'D:\PASS_AI\TEST\automated\pass-ai-fire-workspace-20261022-100000-aaaaaaaa\..\other',
    'E:\CRAFT-FIRE\cache',
    'D:\PASS_AI\TEST\automated',
    'relative\path'
)) {
    $rejected = $false
    try { $null = Assert-FireEvidencePath -Path $path } catch { $rejected = $true }
    $results.Add([pscustomobject]@{name=('evidence-path-rejected:'+$path);ok=$rejected})
}
$validPath = 'D:\PASS_AI\TEST\automated\pass-ai-fire-workspace-20261022-100000-aaaaaaaa'
$accepted = $false
try { $accepted = (Assert-FireEvidencePath $validPath) -ceq $validPath } catch { }
$results.Add([pscustomobject]@{name='dedicated-evidence-path-accepted';ok=$accepted})
return $results.ToArray()
