# Explicit source generation from the approved public-document tracking manifest.
[CmdletBinding()]
param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'Workspace.Common.psm1') -Force
if($root -cne 'E:\CRAFT-FIRE'){throw 'Unexpected source root'}
Assert-FirePlainPath $root
$inputFile=Join-Path $root 'docs\FIRE_FEATURE_CATALOG.json'
$outputFile=Join-Path $root 'src\Core\Catalog.tsv'
Assert-FirePlainPath $inputFile
Assert-FirePlainPath $outputFile
$catalog=Get-Content -LiteralPath $inputFile -Raw -Encoding UTF8 | ConvertFrom-Json
$rows=@($catalog.requirements | ForEach-Object {
 foreach($field in @($_.requirement_id,$_.domain,$_.title)){if([string]::IsNullOrWhiteSpace($field) -or $field -match '[\t\r\n]'){throw 'Invalid catalog field'}}
 '{0}{1}{2}{1}{3}' -f $_.requirement_id,"`t",$_.domain,$_.title
})
$text=[string]::Join("`n",$rows)+"`n"
if($CheckOnly){if(-not(Test-Path -LiteralPath $outputFile) -or [IO.File]::ReadAllText($outputFile) -cne $text){throw 'Catalog source is stale'}; 'Catalog source matches public tracking manifest';return}
[IO.File]::WriteAllText($outputFile,$text,(New-Object Text.UTF8Encoding($false)))
