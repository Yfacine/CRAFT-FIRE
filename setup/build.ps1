[CmdletBinding()]
param([string]$ArtifactsRoot='',
 [ValidateRange(1,3600)][int]$SdkTimeoutSeconds=30,
 [ValidateRange(1,3600)][int]$RestoreTimeoutSeconds=180,
 [ValidateRange(1,3600)][int]$BuildTimeoutSeconds=120)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Build.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Process.Common.psm1') -Force
$inputData=Get-FireBuildInputs
if(-not $ArtifactsRoot){$ArtifactsRoot='D:\PASS_AI\TEST\automated\pass-ai-fire-build-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)}
$run=Assert-FireBuildRoot $ArtifactsRoot
if(Test-Path -LiteralPath $run){throw 'Build run directory already exists; use a fresh run'}
[void][IO.Directory]::CreateDirectory($run)
$lease=[IO.File]::Open((Join-Path $run '.build.lock'),[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$saved=@{}; $receipt=$null; $stages=New-Object 'System.Collections.Generic.List[string]'
try {
 $saved=Set-FireBuildEnvironment $run
 Push-Location $inputData.root
 try {
  $stage=Invoke-FireOwnedProcess -Executable $inputData.sdk -Arguments @('--version') -RunRoot $run -Stage 'sdk-version' -TimeoutSeconds $SdkTimeoutSeconds
  $stages.Add($stage.receipt_path)
  if($stage.result -cne 'PASS'){throw 'SDK version process failed; inspect sdk-version-process.json'}
  $sdkVersion=([IO.File]::ReadAllText($stage.log)).Trim()
  if($sdkVersion -cne '8.0.426'){throw 'Approved SDK version mismatch'}
  $props=@("-p:FireArtifactsRoot=$run","-p:FireCadRoot=$($inputData.cad)","-p:FireVersion=$($inputData.version)",'-p:FireSupportedEntry=true','-p:UseSharedCompilation=false','-nodeReuse:false')
  $manifest=@(Get-ChildItem -LiteralPath $inputData.root -Recurse -File -Force | Where-Object {$_.FullName -notmatch '\\.git\\'} | ForEach-Object {[pscustomobject]@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
  $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run 'source-manifest.json') -Encoding UTF8
  $stage=Invoke-FireOwnedProcess -Executable $inputData.sdk -Arguments (@('restore','PassAiFire.sln','--locked-mode','--configfile','NuGet.config')+$props) -RunRoot $run -Stage 'restore' -TimeoutSeconds $RestoreTimeoutSeconds
  $stages.Add($stage.receipt_path)
  if($stage.result -cne 'PASS'){throw 'Locked restore failed; inspect restore-process.json'}
  $stage=Invoke-FireOwnedProcess -Executable $inputData.sdk -Arguments (@('build','PassAiFire.sln','-c','Release','--no-restore','--disable-build-servers')+$props) -RunRoot $run -Stage 'build' -TimeoutSeconds $BuildTimeoutSeconds
  $stages.Add($stage.receipt_path)
  if($stage.result -cne 'PASS'){throw 'Build failed; inspect build-process.json'}
  $outputs=@(foreach($entry in @(@('PassAiFire.Core','PassAiFire.Core.dll'),@('PassAiFire.AutoCAD2024','PassAiFire.AutoCAD2024.dll'),@('PassAiFire.Tests','PassAiFire.Tests.exe'))){
   $path=Join-Path $run ('bin\'+$entry[0]+'\Release\net48\'+$entry[1])
   $item=Get-Item -LiteralPath $path
   if([Reflection.AssemblyName]::GetAssemblyName($path).Version.ToString(3) -cne $inputData.version){throw 'Output assembly version mismatch'}
   [pscustomobject]@{path=$path;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
  })
  if(@(Get-ChildItem -LiteralPath (Join-Path $run 'bin') -Recurse -File | Where-Object {$_.Name -in @('AcMgd.dll','AcCoreMgd.dll','AcDbMgd.dll')}).Count){throw 'Autodesk API files must not be copied to output'}
  foreach($row in $manifest){if((Get-FileHash -LiteralPath $row.path -Algorithm SHA256).Hash -cne $row.sha256){throw 'Build mutated product sources'}}
  $receipt=[ordered]@{schema_version='1.0.0';result='PASS';timestamp_utc=[DateTimeOffset]::UtcNow.ToString('o');source_root=$inputData.root;artifacts_root=$run;version=$inputData.version;sdk=$inputData.sdk;sdk_version=$sdkVersion;sdk_sha256=(Get-FileHash -LiteralPath $inputData.sdk -Algorithm SHA256).Hash;framework='net48';platform='x64';references=$inputData.references;outputs=$outputs;restore='LOCKED';dependency='Microsoft.NETFramework.ReferenceAssemblies.net48/1.0.3';cad_execution='NOT RUN';feature_implementation='NOT STARTED'}
 } finally {Pop-Location}
} catch {
 $receipt=[ordered]@{result='FAIL';timestamp_utc=[DateTimeOffset]::UtcNow.ToString('o');artifacts_root=$run;error=$_.Exception.Message}
} finally {
 Restore-FireBuildEnvironment $saved
 $lease.Dispose()
}
$receipt['process_stages']=$stages.ToArray()
$receipt['process_limits']=[ordered]@{sdk_seconds=$SdkTimeoutSeconds;restore_seconds=$RestoreTimeoutSeconds;build_seconds=$BuildTimeoutSeconds;descendant_grace_seconds=2;cleanup_seconds=5}
$json=$receipt | ConvertTo-Json -Depth 10
$json | Set-Content -LiteralPath (Join-Path $run 'build-receipt.json') -Encoding UTF8
$json
if($receipt.result -ne 'PASS'){exit 1}
exit 0
