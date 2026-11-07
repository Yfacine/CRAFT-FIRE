[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'Workspace.Common.psm1') -Force
Assert-FirePlainPath -Path $sourceRoot
if ($sourceRoot -ine 'E:\CRAFT-FIRE') { throw 'Unexpected workspace root.' }
$config = Get-Content -LiteralPath (Join-Path $sourceRoot 'orchestration\workspace.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not (Test-FireWorkspaceConfig $config)) { throw 'Workspace configuration failed validation.' }
$tools = @()
foreach ($name in @('dotnet','autocad')) {
    $path = [string]$config.tool_candidates.$name
    $tools += [pscustomobject]@{name=$name;path=$path;file_present=(Test-Path -LiteralPath $path -PathType Leaf);execution='NOT RUN';ownership='existing installation; read-only candidate'}
}
[ordered]@{
    workspace_id=$config.workspace_id;source_root=$sourceRoot;stage=$config.stage;
    powershell_version=$PSVersionTable.PSVersion.ToString();tools=$tools;
    product_build='NOT RUN';cad_load='NOT RUN';dependency_installation='NOT APPROVED';
    product_profile=$config.product_profile_status;target_cad=$config.target_cad;target_framework=$config.target_framework;
    execution_root=$config.execution_root;writes_performed=$false
} | ConvertTo-Json -Depth 6
