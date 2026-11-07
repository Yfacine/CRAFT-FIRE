# Shared LIVE acceptance rules. Regression evidence is never live completion evidence.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
# Build imports Workspace with -Force. Load Build first, then bind private dependency commands.
# Calling CommandInfo objects avoids relying on commands surviving in a caller's scope.
$script:AcBuildModule=Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'setup\Build.Common.psm1') -Force -Scope Local -PassThru
$script:AcWorkspaceModule=Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'setup\Workspace.Common.psm1') -Scope Local -PassThru

function Assert-AcPlainPath {
 param([Parameter(Mandatory=$true)][string]$Path)
 & ($script:AcWorkspaceModule.ExportedCommands['Assert-FirePlainPath']) -Path $Path
}
function Test-AcWorkspaceConfig {
 param([Parameter(Mandatory=$true)]$Config)
 & ($script:AcWorkspaceModule.ExportedCommands['Test-FireWorkspaceConfig']) -Config $Config
}

function Assert-Ac {
 param([string]$Id,[bool]$Ok,[string]$Detail)
 if(-not $Ok){throw ('['+$Id+'] '+$Detail)}
}
function Get-AcValue {
 param($Value,[string]$Name)
 if($null -eq $Value){return $null}
 $p=$Value.PSObject.Properties[$Name]
 if($null -ne $p){return $p.Value}
 return $null
}
function Assert-AcLive {
 param($Value,[string]$Context='input',[int]$Depth=0)
 Assert-Ac 'AC-JSON-DEPTH' ($Depth -le 50) $Context
 if($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]){return}
 if($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary] -and $Value -isnot [pscustomobject]){
  foreach($item in $Value){Assert-AcLive $item $Context ($Depth+1)}
  return
 }
 $properties=if($Value -is [System.Collections.IDictionary]){
  @($Value.Keys | ForEach-Object {[pscustomobject]@{Name=[string]$_;Value=$Value[$_]}})
 }else{@($Value.PSObject.Properties)}
 foreach($p in $properties){
  $key=($p.Name -replace '[_-]','').ToLowerInvariant()
  # Marker presence is rejected, including false/empty markers; live producers do not emit these keys.
  Assert-Ac 'AC-SYNTHETIC' ($key -notin @('fixturescope','fixture','isfixture','synthetic','syntheticscope','issynthetic','testonly','testmode','mock','mocked','simulation','simulated')) ($Context+'.'+$p.Name)
  if($p.Value -is [string] -and $key -in @('scope','mode','result','status','purpose','assessment','evidencekind','evidencetype')){
   Assert-Ac 'AC-SYNTHETIC' ($p.Value -notmatch '(?i)(?:^|[^a-z])(synthetic|fixture|mock|test[_ -]?only|self[_ -]?test)(?:$|[^a-z])') ($Context+'.'+$p.Name)
  }
  Assert-AcLive $p.Value ($Context+'.'+$p.Name) ($Depth+1)
 }
}
function Assert-AcEvidencePath {
 param([string]$Path)
 Assert-Ac 'AC-EVIDENCE-PATH' ([IO.Path]::IsPathRooted($Path)) $Path
 $full=[IO.Path]::GetFullPath($Path)
 Assert-Ac 'AC-EVIDENCE-PATH' ($full -ceq $Path -and $full.StartsWith('D:\PASS_AI\TEST\automated\',[StringComparison]::OrdinalIgnoreCase) -and $full.IndexOf(':',2) -lt 0) $Path
 try{Assert-AcPlainPath $full}catch{throw ('[AC-EVIDENCE-PATH] '+$_.Exception.Message)}
 return $full
}
function Get-AcEvidenceRoot {
 param([string]$ManifestPath)
 Assert-Ac 'AC-MANIFEST-PATH' ($ManifestPath -cmatch '^D:\\PASS_AI\\TEST\\automated\\pass-ai-fire-foundation-[a-zA-Z0-9-]+\\acceptance-input\.json$') 'Exact foundation acceptance manifest required'
 $null=Assert-AcEvidencePath $ManifestPath
 return [IO.Path]::GetDirectoryName($ManifestPath)
}
function Read-AcJson {
 param([string]$Path,[string]$Context='evidence')
 $null=Assert-AcEvidencePath $Path
 Assert-Ac 'AC-EVIDENCE-READ' (Test-Path -LiteralPath $Path -PathType Leaf) ($Context+': '+$Path)
 try{$value=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json}catch{throw ('[AC-JSON] '+$Context+': '+$_.Exception.Message)}
 Assert-AcLive $value $Context
 return ,$value
}
function Get-AcCurrentInputs {
 $root='E:\CRAFT-FIRE'
 & ($script:AcBuildModule.ExportedCommands['Assert-FireSourceTree']) -Root $root
 $files=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {$_.FullName -notmatch '\\.git\\'})
 $result=@($files | Where-Object {
  $relative=$_.FullName.Substring($root.Length+1)
  $relative -match '^(src|setup|tests|orchestration)\\' -or
  ($relative -notmatch '\\' -and $_.Extension -ine '.md') -or
  ($relative -match '^docs\\' -and $_.Extension -in @('.json','.tsv'))
 } | Sort-Object FullName | ForEach-Object {
  [pscustomobject]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
 })
 foreach($required in @('version.json','global.json','Directory.Build.props','Directory.Build.targets','NuGet.config','PassAiFire.sln','src\Core\Foundation.cs','src\Core\Catalog.tsv','docs\FIRE_FEATURE_CATALOG.json','docs\FIRE_SOURCE_REGISTER.json','setup\run_tests.ps1','tests\verify_acceptance.ps1')){
  Assert-Ac 'AC-SOURCE-REQUIRED' (@($result | Where-Object {$_.path -ceq (Join-Path $root $required)}).Count -eq 1) $required
 }
 Assert-Ac 'AC-SOURCE-CURRENT-EMPTY' ($result.Count -gt 0) 'Current executable inputs must be non-empty'
 return $result
}
function Assert-AcSourceManifest {
 param([string]$Path,[string]$Context)
 Assert-Ac 'AC-SOURCE-MISSING-MANIFEST' (Test-Path -LiteralPath $Path -PathType Leaf) $Context
 # Build snapshots include documentation; only known Markdown documentation is allowed outside the executable input set.
 $raw=Get-Content -LiteralPath $Path -Raw -Encoding UTF8
 Assert-Ac 'AC-SOURCE-FORMAT' ($raw.TrimStart().StartsWith('[')) ($Context+': JSON array required')
 $rows=Read-AcJson $Path ($Context+':source-manifest')
 Assert-Ac 'AC-SOURCE-EMPTY' ($null -ne $rows -and @($rows).Count -gt 0) $Context
 $current=@(Get-AcCurrentInputs)
 $expected=@{};foreach($row in $current){$expected[$row.path]=$row.sha256}
 $seen=@{};$recorded=@{}
 foreach($row in $rows){
  $path=Get-AcValue $row 'path';$hash=Get-AcValue $row 'sha256'
  Assert-Ac 'AC-SOURCE-FORMAT' ($path -is [string] -and $hash -is [string] -and $hash -cmatch '^[A-Fa-f0-9]{64}$') $Context
  Assert-Ac 'AC-SOURCE-PATH' ([IO.Path]::IsPathRooted($path) -and $path.StartsWith('E:\CRAFT-FIRE\',[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFullPath($path) -ceq $path -and $path.IndexOf(':',2) -lt 0) ($Context+': '+$path)
  Assert-Ac 'AC-SOURCE-DUPLICATE' (-not $seen.ContainsKey($path)) ($Context+': '+$path)
  $seen[$path]=$true
  if($expected.ContainsKey($path)){
   $recorded[$path]=$hash
  }else{
   $relative=$path.Substring('E:\CRAFT-FIRE\'.Length)
   Assert-Ac 'AC-SOURCE-SET' ($relative -match '^(?:(?:docs|plans)\\.*|[^\\]+)\.md$') ($Context+': unexpected '+$path)
  }
 }
 Assert-Ac 'AC-SOURCE-SET' ($recorded.Count -eq $expected.Count -and @($expected.Keys | Where-Object {-not $recorded.ContainsKey($_)}).Count -eq 0) ($Context+': current input set differs')
 foreach($path in $expected.Keys){Assert-Ac 'AC-SOURCE-HASH' ($recorded[$path] -ieq $expected[$path]) ($Context+': '+$path)}
}
function Assert-AcCounts {
 param($Value,[string]$Context,[string]$RowsName='checks',[switch]$NoResult)
 $rows=Get-AcValue $Value $RowsName
 $passed=Get-AcValue $Value 'passed';$failed=Get-AcValue $Value 'failed'
 $numeric=($passed -is [int] -or $passed -is [long]) -and ($failed -is [int] -or $failed -is [long])
 Assert-Ac 'AC-RECEIPT-COUNTS' ($numeric -and $null -ne $rows -and @($rows).Count -gt 0) $Context
 $bad=@($rows | Where-Object {(Get-AcValue $_ 'ok') -isnot [bool] -or (Get-AcValue $_ 'ok') -ne $true -or [string]::IsNullOrWhiteSpace((Get-AcValue $_ 'name'))})
 Assert-Ac 'AC-RECEIPT-COUNTS' ($failed -eq 0 -and $passed -eq @($rows).Count -and $bad.Count -eq 0) $Context
 if(-not $NoResult){Assert-Ac 'AC-RECEIPT-PASS' ((Get-AcValue $Value 'result') -ceq 'PASS') $Context}
}
function Assert-AcBuild {
 param($Build,[string]$ReceiptPath,[string]$Context,[switch]$RequireCoreLog)
 Assert-AcLive $Build $Context
 $inputs=& ($script:AcBuildModule.ExportedCommands['Get-FireBuildInputs'])
 $run=Get-AcValue $Build 'artifacts_root'
 try{$null=& ($script:AcBuildModule.ExportedCommands['Assert-FireBuildRoot']) -Path $run}catch{throw ('[AC-BUILD-PATH] '+$Context+': '+$_.Exception.Message)}
 Assert-Ac 'AC-BUILD-PATH' ($ReceiptPath -ceq (Join-Path $run 'build-receipt.json')) $Context
 Assert-Ac 'AC-BUILD-SCOPE' ($Build.result -ceq 'PASS' -and $Build.source_root -ceq $inputs.root -and $Build.version -ceq $inputs.version -and $Build.framework -ceq 'net48' -and $Build.platform -ceq 'x64' -and $Build.restore -ceq 'LOCKED' -and $Build.sdk_version -ceq '8.0.426' -and $Build.dependency -ceq 'Microsoft.NETFramework.ReferenceAssemblies.net48/1.0.3') $Context
 Assert-Ac 'AC-BUILD-SDK' ($Build.sdk -ceq $inputs.sdk -and $Build.sdk_sha256 -ieq (Get-FileHash -LiteralPath $inputs.sdk -Algorithm SHA256).Hash) $Context
 Assert-Ac 'AC-BUILD-REFERENCES' (@($Build.references).Count -eq $inputs.references.Count) $Context
 foreach($reference in $inputs.references){
  $matches=@($Build.references | Where-Object {$_.path -ceq $reference.path})
  Assert-Ac 'AC-BUILD-REFERENCES' ($matches.Count -eq 1 -and $matches[0].sha256 -ieq $reference.sha256 -and $matches[0].version -ceq $reference.version) $Context
 }
 $expected=@('bin\PassAiFire.Core\Release\net48\PassAiFire.Core.dll','bin\PassAiFire.AutoCAD2024\Release\net48\PassAiFire.AutoCAD2024.dll','bin\PassAiFire.Tests\Release\net48\PassAiFire.Tests.exe')
 Assert-Ac 'AC-BUILD-OUTPUTS' (@($Build.outputs).Count -eq 3) $Context
 for($i=0;$i -lt 3;$i++){
  $output=$Build.outputs[$i];$path=Join-Path $run $expected[$i]
  Assert-Ac 'AC-BUILD-OUTPUTS' ($output.path -ceq $path -and $output.sha256 -cmatch '^[A-Fa-f0-9]{64}$') ($Context+': '+$expected[$i])
  $null=Assert-AcEvidencePath $path
  Assert-Ac 'AC-BUILD-OUTPUT-HASH' ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ieq $output.sha256) $Context
  Assert-Ac 'AC-BUILD-IDENTITY' ((& ($script:AcBuildModule.ExportedCommands['Get-FirePeMachine']) -Path $path) -eq 0x8664 -and [Reflection.AssemblyName]::GetAssemblyName($path).Version.ToString(3) -ceq $inputs.version) $Context
 }
 $sourcePath=Join-Path $run 'source-manifest.json'
 $null=Assert-AcEvidencePath $sourcePath
 Assert-AcSourceManifest $sourcePath $Context
 if($RequireCoreLog){
  $logPath=Join-Path $run 'core-tests.log';$null=Assert-AcEvidencePath $logPath
  $log=[IO.File]::ReadAllText($logPath)
  Assert-Ac 'AC-CORE-LOG' ($log.Contains('FIRE_TEST_RESULT checks=95 failed=0') -and $log -notmatch '(?m)^FAIL ') $Context
 }
}
Export-ModuleMember -Function Assert-AcPlainPath,Test-AcWorkspaceConfig,Assert-Ac,Get-AcValue,Assert-AcLive,Assert-AcEvidencePath,Get-AcEvidenceRoot,Read-AcJson,Get-AcCurrentInputs,Assert-AcSourceManifest,Assert-AcCounts,Assert-AcBuild
