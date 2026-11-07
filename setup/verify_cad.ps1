[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$BuildReceipt,
 [Parameter(Mandatory=$true)][string]$ApprovalPath,
 [Parameter(Mandatory=$true)][string]$ApprovalSha256,
 [Parameter(Mandatory=$true)][string]$ExpectedTemplateSha256,
 [ValidateRange(10,180)][int]$TimeoutSeconds=120,
 [switch]$ValidateOnly
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Build.Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Workspace.Common.psm1') -Force
$inputs=Get-FireBuildInputs
$run=Assert-FireBuildRoot ([IO.Path]::GetDirectoryName($BuildReceipt))
if($BuildReceipt -cne (Join-Path $run 'build-receipt.json')){throw 'Exact build receipt required'}
foreach($p in @($BuildReceipt,$ApprovalPath)){Assert-FirePlainPath $p}
if($ApprovalPath -cnotmatch '^D:\\PASS_AI\\TEST\\automated\\pass-ai-fire-foundation-[a-zA-Z0-9-]+\\session-approval.json$'){throw 'Dedicated approval record required'}
if($ApprovalSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $ApprovalPath -Algorithm SHA256).Hash -ine $ApprovalSha256){throw 'Approval record hash mismatch'}
$approval=Get-Content -LiteralPath $ApprovalPath -Raw -Encoding UTF8 | ConvertFrom-Json
if($approval.decision -cne 'APPROVED' -or $approval.product_root -cne $inputs.root -or $approval.scope -cne 'foundation-registration-build-isolated-cad-diagnostics' -or $approval.host -cne 'AutoCAD2024' -or ($approval.commands -join ',') -cne 'PASSAIFIRE_ABOUT,PASSAIFIRE_STATUS'){throw 'Approval scope mismatch'}
foreach($key in @('drawing_edits','global_settings','feature_development')){if($approval.$key -isnot [bool] -or $approval.$key -ne $false){throw 'Approval exceeds diagnostic-only scope'}}
$build=Get-Content -LiteralPath $BuildReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
if($build.result -cne 'PASS' -or $build.source_root -cne $inputs.root -or $build.artifacts_root -cne $run -or $build.version -cne $inputs.version -or $build.framework -cne 'net48' -or $build.platform -cne 'x64'){throw 'Build receipt mismatch'}
$plugin=Join-Path $run 'bin\PassAiFire.AutoCAD2024\Release\net48\PassAiFire.AutoCAD2024.dll'
$core=Join-Path $run 'bin\PassAiFire.Core\Release\net48\PassAiFire.Core.dll'
foreach($path in @($plugin,$core)){
 Assert-FirePlainPath $path
 $row=@($build.outputs | Where-Object {$_.path -ceq $path})
 if($row.Count -ne 1 -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $row[0].sha256){throw 'Built DLL identity mismatch'}
 if([Reflection.AssemblyName]::GetAssemblyName($path).Version.ToString(3) -cne $inputs.version){throw 'Built DLL version mismatch'}
}
foreach($row in $build.references){if((Get-FileHash -LiteralPath $row.path -Algorithm SHA256).Hash -cne $row.sha256){throw 'CAD reference changed since build'}}
$template='C:\Users\SYBME_PC\AppData\Local\Autodesk\AutoCAD 2024\R24.3\kor\Template\acadiso.dwt'
$engine=Join-Path $inputs.cad 'accoreconsole.exe'
foreach($path in @($template,$engine)){Assert-FirePlainPath $path}
if($ExpectedTemplateSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash -ine $ExpectedTemplateSha256){throw 'Template hash mismatch'}
if((Get-Item -LiteralPath $engine).VersionInfo.FileVersion -notmatch '^24\.3\.'){throw 'Unexpected CAD engine version'}
if($ValidateOnly){[pscustomobject]@{result='PASS';mode='VALIDATE ONLY';process_started=$false;build_receipt=$BuildReceipt}|ConvertTo-Json;exit 0}
$work=Join-Path $run ('cad-smoke-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$pluginDir=Join-Path $work 'plugin'
[void][IO.Directory]::CreateDirectory($pluginDir)
$drawing=Join-Path $work 'foundation-input.dwg'
Copy-Item -LiteralPath $template -Destination $drawing
[IO.File]::SetAttributes($drawing,[IO.FileAttributes]::ReadOnly)
foreach($path in @($plugin,$core)){Copy-Item -LiteralPath $path -Destination $pluginDir}
$script=Join-Path $work 'diagnostic.scr'
$ownedPlugin=Join-Path $pluginDir 'PassAiFire.AutoCAD2024.dll'
$lines=@(
 ('(setvar "TRUSTEDPATHS" (strcat (getvar "TRUSTEDPATHS") ";'+$pluginDir.Replace('\','/')+'"))'),
 '_.NETLOAD',
 ('"'+$ownedPlugin.Replace('\','/')+'"'),
 'PASSAIFIRE_ABOUT',
 'PASSAIFIRE_STATUS',
 '_.QUIT',
 '_Y',
 ''
)
[IO.File]::WriteAllText($script,([string]::Join("`r`n",$lines)+"`r`n"),[Text.Encoding]::ASCII)
$before=@(Get-Process -Name acad,accoreconsole -ErrorAction SilentlyContinue | ForEach-Object {[pscustomobject]@{id=$_.Id;name=$_.ProcessName;started=$_.StartTime.ToUniversalTime().ToString('o')}})
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=$engine
$profileName='PASSAIFIRE_'+[Guid]::NewGuid().ToString('N')
$info.Arguments='/i "'+$drawing+'" /s "'+$script+'" /isolate '+$profileName+' "'+(Join-Path $work 'profile')+'" /l ko-KR /readonly'
$info.WorkingDirectory=$work
$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
$info.EnvironmentVariables['TEMP']=$work;$info.EnvironmentVariables['TMP']=$work
$proc=New-Object Diagnostics.Process
$proc.StartInfo=$info
$out=New-Object IO.MemoryStream;$err=New-Object IO.MemoryStream
$result='FAIL';$failure='';$warnings=@();$timedOut=$false;$ownedPid=$null;$exitCode=$null;$stopped=$false
try{
 if(-not $proc.Start()){throw 'CAD engine did not start'}
 $ownedPid=$proc.Id
 $copyOut=$proc.StandardOutput.BaseStream.CopyToAsync($out)
 $copyErr=$proc.StandardError.BaseStream.CopyToAsync($err)
 if(-not $proc.WaitForExit($TimeoutSeconds*1000)){$timedOut=$true;$proc.Kill();$proc.WaitForExit();throw 'Owned CAD diagnostic timed out'}
 [void]$copyOut.GetAwaiter().GetResult();[void]$copyErr.GetAwaiter().GetResult()
 $exitCode=$proc.ExitCode;$stopped=$proc.HasExited
 if($exitCode -ne 0){throw "CAD exit code $exitCode"}
}catch{$failure=$_.Exception.Message}finally{
 if($null -ne $ownedPid){if(-not $proc.HasExited){$proc.Kill();$proc.WaitForExit()};$stopped=$proc.HasExited}
 $outBytes=$out.ToArray();$errBytes=$err.ToArray()
 [IO.File]::WriteAllBytes((Join-Path $work 'stdout.raw'),$outBytes)
 [IO.File]::WriteAllBytes((Join-Path $work 'stderr.raw'),$errBytes)
 function Decode([byte[]]$bytes){if($bytes.Length -gt 1 -and @($bytes|Where-Object {$_ -eq 0}).Count -gt $bytes.Length/5){return [Text.Encoding]::Unicode.GetString($bytes)};return [Text.Encoding]::UTF8.GetString($bytes)}
 $stdout=Decode $outBytes;$stderr=Decode $errBytes
 [IO.File]::WriteAllText((Join-Path $work 'stdout.log'),$stdout,(New-Object Text.UTF8Encoding($false)))
 [IO.File]::WriteAllText((Join-Path $work 'stderr.log'),$stderr,(New-Object Text.UTF8Encoding($false)))
 $out.Dispose();$err.Dispose();$proc.Dispose()
}
$checks=New-Object 'System.Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Ok){$checks.Add([pscustomobject]@{name=$Name;ok=$Ok})}
Check 'engine-exited-successfully' ($exitCode -eq 0 -and $stopped -and -not $timedOut -and -not $failure)
Check 'about-actual-output' ($stdout.Contains("PASS_AI_FIRE $($inputs.version) | AutoCAD2024/net48/x64 | foundation-only"))
Check 'status-actual-output' ($stdout.Contains('PASS_AI_FIRE_STATUS tracked=76 implemented=0 target=FIRE2025+ features=DISABLED'))
Check 'explicit-quit-command' ($stdout -match '_\.QUIT' -and $stdout -match '_Y')
Check 'template-preserved' ((Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash -ieq $ExpectedTemplateSha256)
Check 'owned-drawing-unchanged' ((Get-FileHash -LiteralPath $drawing -Algorithm SHA256).Hash -ieq $ExpectedTemplateSha256)
$after=@(Get-Process -Name acad,accoreconsole -ErrorAction SilentlyContinue | ForEach-Object {[pscustomobject]@{id=$_.Id;name=$_.ProcessName;started=$_.StartTime.ToUniversalTime().ToString('o')}})
foreach($item in $before){Check ('existing-cad-process-preserved:'+$item.id) (@($after|Where-Object {$_.id -eq $item.id -and $_.started -ceq $item.started}).Count -eq 1)}
Check 'owned-cad-process-stopped' ($null -ne $ownedPid -and -not (Get-Process -Id $ownedPid -ErrorAction SilentlyContinue))
$combined=$stdout+"`n"+$stderr
# An engine temp-log cleanup warning is classified narrowly and preserved; no files are deleted here.
$unclassified=$combined
if($null -ne $ownedPid){
 $knownPattern='(?im)^ERROR: Can''t delete temp file '+[regex]::Escape((Join-Path $work ('accc'+$ownedPid+'2.')))+' \(errno=13\)\.\s*$'
 foreach($m in [regex]::Matches($combined,$knownPattern)){$warnings+=$m.Value.Trim()}
 $unclassified=[regex]::Replace($combined,$knownPattern,'')
}
Check 'no-unclassified-command-or-load-errors' ($unclassified -notmatch '(?im)\bERROR\b|Unknown command|\uC54C \uC218 \uC5C6\uB294 \uBA85\uB839|\uBA85\uB839\uC744 \uC54C \uC218|Unable to load|\uB85C\uB4DC\uD560 \uC218 \uC5C6|Exception|FATAL')
$failed=@($checks|Where-Object {-not $_.ok}).Count
if($failed -eq 0){$result='PASS'}
$receipt=[ordered]@{result=$result;timestamp_utc=[DateTimeOffset]::UtcNow.ToString('o');mode='ACTUAL ISOLATED AUTOCAD2024 CORE CONSOLE';build_receipt=$BuildReceipt;build_receipt_sha256=(Get-FileHash -LiteralPath $BuildReceipt -Algorithm SHA256).Hash;approval_path=$ApprovalPath;approval_sha256=$ApprovalSha256;engine=$engine;engine_sha256=(Get-FileHash -LiteralPath $engine -Algorithm SHA256).Hash;arguments=$info.Arguments;owned_pid=$ownedPid;exit_code=$exitCode;process_stopped=$stopped;timed_out=$timedOut;failure=$failure;passed=$checks.Count-$failed;failed=$failed;checks=$checks.ToArray();warnings=$warnings;template=$template;template_sha256=$ExpectedTemplateSha256;work_root=$work;user_drawing_edit='NOT RUN';global_installation='NOT RUN';fire_features='NOT IMPLEMENTED';cad_processes_before=$before;cad_processes_after=$after}
$json=$receipt|ConvertTo-Json -Depth 10
$json|Set-Content -LiteralPath (Join-Path $work 'cad-receipt.json') -Encoding UTF8
$json
if($failed){exit 1};exit 0
