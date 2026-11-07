Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-FireWorkspaceConfig {
    param([Parameter(Mandatory=$true)]$Config)
    try {
        $exact = @{
            schema_version='1.0.0'; workspace_id='pass-ai-fire'; workspace_root='E:\CRAFT-FIRE';
            development_environment_root='E:\PASS_AI'; planning_root='E:\CRAFT-FIRE\plans';
            execution_root='D:\PASS_AI\TEST'; test_source_root='E:\CRAFT-FIRE\tests';
            workspace_runner='E:\CRAFT-FIRE\setup\run_tests.ps1';
            product_profiles_policy='E:\PASS_AI\orchestration\product-profiles.json';
            stage='foundation-only'; product_profile_status='REGISTERED';
            target_cad='AutoCAD 2024'; target_framework='net48';
            reference_url='https://www.dcs.co.kr/products/fire'
        }
        foreach ($key in $exact.Keys) {
            if ($Config.$key -isnot [string] -or $Config.$key -cne $exact[$key]) { return $false }
        }
        foreach ($key in @('product_implementation_enabled','dependency_installation_approved','cad_execution_approved')) {
            if ($Config.$key -isnot [bool] -or $Config.$key -ne $false) { return $false }
        }
        $expected = @('E:\CRAFT-DreamPlus','E:\PASS_AI\exe','E:\PASS_AI\exe_fb') | Sort-Object
        if ($Config.protected_product_roots -isnot [array]) { return $false }
        $actual = @($Config.protected_product_roots | Sort-Object)
        if ($actual.Count -ne 3 -or @(Compare-Object $expected $actual -CaseSensitive).Count -gt 0) { return $false }
        return $true
    } catch { return $false }
}

function Assert-FirePlainPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $node = Get-Item -LiteralPath $cursor -Force
            if (($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Reparse points are not supported in workspace or evidence paths.'
            }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        $cursor = if ($null -eq $parent) { '' } else { $parent.FullName }
    }
}

function Assert-FireEvidencePath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw 'Evidence path must be absolute.' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    $prefix = 'D:\PASS_AI\TEST\automated\pass-ai-fire-workspace-'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence must stay in a dedicated FIRE workspace run under D:\PASS_AI\TEST\automated.'
    }
    $relative = $full.Substring($prefix.Length)
    if ($relative -notmatch '^[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$') { throw 'Invalid workspace run directory.' }
    Assert-FirePlainPath -Path $full
    return $full
}

Export-ModuleMember -Function Test-FireWorkspaceConfig, Assert-FirePlainPath, Assert-FireEvidencePath
