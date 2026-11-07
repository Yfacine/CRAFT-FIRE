Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Workspace.Common.psm1') -Force

function Assert-FireBuildRoot {
 param([Parameter(Mandatory=$true)][string]$Path)
 if($Path -cnotmatch '^D:\\PASS_AI\\TEST\\automated\\pass-ai-fire-build-[0-9]{8}-[0-9]{6}-[a-f0-9]{8}$'){throw 'Dedicated absolute FIRE build directory required'}
 $full=[IO.Path]::GetFullPath($Path)
 if($full -cne $Path){throw 'Non-canonical build directory rejected'}
 Assert-FirePlainPath $full
 return $full
}
function Assert-FireSourceTree {
 param([string]$Root='E:\CRAFT-FIRE')
 if($Root -cne 'E:\CRAFT-FIRE'){throw 'Unexpected product root'}
 Assert-FirePlainPath $Root
 $queue=New-Object 'System.Collections.Generic.Queue[string]'
 $queue.Enqueue($Root)
 while($queue.Count -gt 0){
  foreach($item in Get-ChildItem -LiteralPath $queue.Dequeue() -Force){
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Source tree reparse points rejected'}
   if($item.PSIsContainer){if($item.Name -ne '.git'){$queue.Enqueue($item.FullName)}}
  }
 }
}
function Get-FireBuildInputs {
 Assert-FireSourceTree
 $root='E:\CRAFT-FIRE'
 $workspace=Get-Content -LiteralPath (Join-Path $root 'orchestration\workspace.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if(-not(Test-FireWorkspaceConfig $workspace)){throw 'Workspace configuration mismatch'}
 $sdk='E:\PASS_AI\.tools\pass-ai-pro\dotnet\8.0.426\dotnet.exe'
 $cad='C:\Program Files\Autodesk\AutoCAD 2024'
 foreach($path in @($sdk,$cad)){Assert-FirePlainPath $path}
 if(-not(Test-Path -LiteralPath $sdk -PathType Leaf)){throw 'Approved SDK missing'}
 $v=Get-Content -LiteralPath (Join-Path $root 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if($v.version -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+$' -or $v.stage -cne 'foundation-only'){throw 'Unexpected version or development stage'}
 $refs=@(foreach($name in @('AcCoreMgd.dll','AcMgd.dll','AcDbMgd.dll')){
  $path=Join-Path $cad $name
  Assert-FirePlainPath $path
  $item=Get-Item -LiteralPath $path
  if($item.VersionInfo.FileVersion -notmatch '^24\.3\.'){throw 'Only approved AutoCAD 2024 API files supported'}
  [pscustomobject]@{path=$path;version=$item.VersionInfo.FileVersion;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
 })
 [pscustomobject]@{root=$root;sdk=$sdk;cad=$cad;version=$v.version;references=$refs}
}
function Set-FireBuildEnvironment {
 param([Parameter(Mandatory=$true)][string]$RunRoot)
 $null=Assert-FireBuildRoot $RunRoot
 $values=@{TEMP=(Join-Path $RunRoot 'temp');TMP=(Join-Path $RunRoot 'temp');DOTNET_CLI_HOME=(Join-Path $RunRoot 'dotnet-home');NUGET_PACKAGES=(Join-Path $RunRoot 'packages');NUGET_HTTP_CACHE_PATH=(Join-Path $RunRoot 'nuget-http');DOTNET_CLI_TELEMETRY_OPTOUT='1';DOTNET_SKIP_FIRST_TIME_EXPERIENCE='1';DOTNET_NOLOGO='1';DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE='true';MSBUILDDISABLENODEREUSE='1'}
 foreach($key in @('TEMP','DOTNET_CLI_HOME','NUGET_PACKAGES','NUGET_HTTP_CACHE_PATH')){[void][IO.Directory]::CreateDirectory($values[$key])}
 $saved=@{}
 foreach($key in $values.Keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$values[$key],'Process')}
 return $saved
}
function Restore-FireBuildEnvironment {
 param([hashtable]$Saved)
 foreach($key in $Saved.Keys){[Environment]::SetEnvironmentVariable($key,$Saved[$key],'Process')}
}
function Get-FirePeMachine {
 param([Parameter(Mandatory=$true)][string]$Path)
 $bytes=[IO.File]::ReadAllBytes($Path)
 if($bytes.Length -lt 64 -or $bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a){throw 'Invalid DOS header'}
 $offset=[BitConverter]::ToInt32($bytes,0x3c)
 if($offset -lt 64 -or $offset -gt $bytes.Length-6 -or [BitConverter]::ToUInt32($bytes,$offset) -ne 0x4550){throw 'Invalid PE header'}
 return [BitConverter]::ToUInt16($bytes,$offset+4)
}
Export-ModuleMember -Function Assert-FireBuildRoot,Assert-FireSourceTree,Get-FireBuildInputs,Set-FireBuildEnvironment,Restore-FireBuildEnvironment,Get-FirePeMachine
