param([Parameter(Mandatory=$true)]$Build)
$ErrorActionPreference='Stop'
$root='E:\CRAFT-FIRE'
$rows=New-Object 'System.Collections.Generic.List[object]'
function Check([string]$Name,[bool]$Ok){$rows.Add([pscustomobject]@{name=$Name;ok=$Ok})}
foreach($bad in @('E:\CRAFT-FIRE\bin','D:\PASS_AI\TEST_OTHER\automated\pass-ai-fire-build-20261023-100000-aaaaaaaa','D:\PASS_AI\TEST\automated\pass-ai-fire-build-20261023-100000-aaaaaaaa\..\other','D:\PASS_AI\TEST\automated\pass-ai-fire-build-20261023-100000-aaaaaaaa;bad','relative')){
 $rejected=$false;try{$null=Assert-FireBuildRoot $bad}catch{$rejected=$true};Check ('reject-build-path:'+$bad) $rejected
}
$fixture=Join-Path $Build.artifacts_root 'path-fixtures'
$plain=Join-Path $fixture 'plain'
[void][IO.Directory]::CreateDirectory($plain)
$link=Join-Path $fixture 'junction'
[void](New-Item -ItemType Junction -Path $link -Target $plain)
Import-Module (Join-Path $root 'setup\Workspace.Common.psm1') -Force
$rejected=$false;try{Assert-FirePlainPath (Join-Path $link 'child')}catch{$rejected=$true}
Check 'reject-reparse-point-ancestor' $rejected
$leasePath=Join-Path $fixture 'exclusive.lock'
$first=[IO.File]::Open($leasePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{$rejected=$false;try{$second=[IO.File]::Open($leasePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$second.Dispose()}catch{$rejected=$true};Check 'exclusive-build-lease-contention' $rejected}finally{$first.Dispose()}
$catalog=Get-Content -LiteralPath (Join-Path $root 'docs\FIRE_FEATURE_CATALOG.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$tsv=[IO.File]::ReadAllLines((Join-Path $root 'src\Core\Catalog.tsv'))
Check 'tracking-count-is-manifest-owned' ($tsv.Count -eq $catalog.requirements.Count -and $tsv.Count -eq $catalog.counts.tracked_rows)
$hostSource=Get-Content -LiteralPath (Join-Path $root 'src\Hosts\AutoCAD2024\Diagnostics.cs') -Raw
$commands=@([regex]::Matches($hostSource,'CommandMethod\("([A-Z_]+)"') | ForEach-Object {$_.Groups[1].Value})
Check 'only-two-diagnostic-commands' ($commands.Count -eq 2 -and @($commands|Where-Object {$_ -cnotin @('PASSAIFIRE_ABOUT','PASSAIFIRE_STATUS')}).Count -eq 0)
Check 'no-drawing-write-API' ($hostSource -notmatch 'StartTransaction|AppendEntity|WriteDwgFile|SaveAs|SetSystemVariable|SendStringToExecute')
foreach($project in @('src\Core','src\Hosts\AutoCAD2024','tests\Core')){
 $lock=Get-Content -LiteralPath (Join-Path $root "$project\packages.lock.json") -Raw | ConvertFrom-Json
 $deps=$lock.dependencies.'.NETFramework,Version=v4.8'
 $packages=@($deps.PSObject.Properties | Where-Object {$_.Value.type -ne 'Project'})
 Check ('single-pinned-package:'+$project) ($packages.Count -eq 1 -and $packages[0].Name -ceq 'Microsoft.NETFramework.ReferenceAssemblies.net48' -and $packages[0].Value.resolved -ceq '1.0.3' -and $packages[0].Value.contentHash -ceq 'zMk4D+9zyiEWByyQ7oPImPN/Jhpj166Ky0Nlla4eXlNL8hI/BtSJsgR8Inldd4NNpIAH3oh8yym0W2DrhXdSLQ==')
}
$generated=@(Get-ChildItem -LiteralPath $root -Recurse -Force | Where-Object {($_.PSIsContainer -and $_.Name -in @('bin','obj','packages','__pycache__')) -or (-not $_.PSIsContainer -and $_.Extension -in @('.dll','.exe','.log','.tmp','.pyc'))})
Check 'no-build-cache-or-output-in-source' ($generated.Count -eq 0)
foreach($output in $Build.outputs){Check ('binary-x64:'+[IO.Path]::GetFileName($output.path)) ((Get-FirePeMachine $output.path) -eq 0x8664)}
$badPe=Join-Path $fixture 'invalid-pe.bin'
[IO.File]::WriteAllBytes($badPe,[byte[]](0,1,2,3))
$rejected=$false;try{$null=Get-FirePeMachine $badPe}catch{$rejected=$true}
Check 'invalid-binary-header-rejected' $rejected
return $rows.ToArray()
