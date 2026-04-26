# Build client.dll and server.dll for Windows (Win32 Release) using the
# installed Visual Studio toolchain. Generates the VS solution via vpc.exe,
# retargets it to the available toolset, then invokes msbuild.

[CmdletBinding()]
param(
    [ValidateSet('Release','Debug')] [string]$Configuration = 'Release',
    [string]$PlatformToolset = 'v143',
    [string]$WindowsSdkVersion = '10.0',
    [switch]$Regenerate,
    [switch]$NoDeploy
)

. "$PSScriptRoot\common.ps1"

$msbuild = Find-MsBuild
if (-not $msbuild) { throw "Could not locate MSBuild via vswhere; install VS 2019/2022 with the C++ workload." }
$devenv  = Find-DevEnv
$vpc     = Join-Path $SrcDir 'devtools\bin\vpc.exe'
if (-not (Test-Path -LiteralPath $vpc)) { throw "vpc.exe not found at $vpc" }

# Project paths in dependency build order. Static libs first, then dlls.
$LibProjects = @(
    'tier1\tier1.vcxproj',
    'mathlib\mathlib.vcxproj',
    'raytrace\raytrace.vcxproj',
    'vgui2\vgui_controls\vgui_controls.vcxproj'
)
$DllProjects = @(
    'game\client\client_tf_mod.vcxproj',
    'game\server\server_tf_mod.vcxproj'
)
$AllProjects = $LibProjects + $DllProjects

# 1. Generate per-project vcxproj files via VPC if any are missing or -Regenerate.
$generated = $true
foreach ($rel in $AllProjects) {
    if (-not (Test-Path -LiteralPath (Join-Path $SrcDir $rel))) { $generated = $false; break }
}

if ($Regenerate) {
    Write-Host "Forcing regeneration of project files."
    Get-ChildItem -Path $SrcDir -Recurse -Include *.vcxproj,*.vcxproj.filters,*.vpc_crc,games.sln |
        Remove-Item -Force -ErrorAction SilentlyContinue
    $generated = $false
}

if (-not $generated) {
    Write-Section "Generating Visual Studio project files (vpc)"
    Push-Location $SrcDir
    try {
        # vpc.exe will report a registry error while writing the .sln on systems
        # without VS2013 installed. The per-project .vcxproj files are still
        # generated correctly, and we drive msbuild against those directly.
        & $vpc /tf_mod +game /mksln games.sln
        $vpcExit = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    foreach ($rel in $AllProjects) {
        if (-not (Test-Path -LiteralPath (Join-Path $SrcDir $rel))) {
            throw "vpc.exe (exit $vpcExit) did not produce expected project: $rel"
        }
    }
    if ($vpcExit -ne 0) {
        Write-Warning "vpc.exe exited with code $vpcExit (expected on machines without VS2013); per-project files were generated, continuing."
    }
}

# 2. Retarget every generated vcxproj to the requested toolset / Windows SDK.
Write-Section "Retargeting projects -> $PlatformToolset (Windows SDK $WindowsSdkVersion)"
$projects = Get-ChildItem -Path $SrcDir -Recurse -Filter *.vcxproj -File
Write-Host ("Found {0} project(s)." -f $projects.Count)
foreach ($proj in $projects) {
    $xml = [xml](Get-Content -LiteralPath $proj.FullName -Raw)
    $ns  = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('m', 'http://schemas.microsoft.com/developer/msbuild/2003')

    # Update <PlatformToolset>.
    $nodes = $xml.SelectNodes('//m:PlatformToolset', $ns)
    foreach ($n in $nodes) { $n.InnerText = $PlatformToolset }

    # Ensure <WindowsTargetPlatformVersion> exists in every PropertyGroup that has
    # a PlatformToolset entry; if not, add one.
    $pgs = $xml.SelectNodes('//m:PropertyGroup', $ns)
    foreach ($pg in $pgs) {
        $pt = $pg.SelectSingleNode('m:PlatformToolset', $ns)
        if (-not $pt) { continue }
        $wt = $pg.SelectSingleNode('m:WindowsTargetPlatformVersion', $ns)
        if (-not $wt) {
            $wt = $xml.CreateElement('WindowsTargetPlatformVersion', $ns.LookupNamespace('m'))
            $wt.InnerText = $WindowsSdkVersion
            [void]$pg.AppendChild($wt)
        } else {
            $wt.InnerText = $WindowsSdkVersion
        }
    }

    # Disable /WX (warnings as errors). Legacy v120-era code triggers numerous
    # narrowing-conversion and shadow warnings under v143 that were not emitted
    # by older compilers; turning /WX off lets the build complete while keeping
    # the warnings visible in the log.
    $waeNodes = $xml.SelectNodes('//m:ClCompile/m:TreatWarningAsError', $ns)
    foreach ($n in $waeNodes) { $n.InnerText = 'false' }

    # The MASM custom-build for pointeroverride.asm hard-codes
    # "$(VCInstallDir)bin\ml.exe", a path layout that disappeared after VS2017.
    # Rewrite to the MSBuild-resolved x86 toolset path so ml.exe is found.
    $cmdNodes = $xml.SelectNodes("//m:CustomBuild/m:Command", $ns)
    foreach ($n in $cmdNodes) {
        if ($n.InnerText -match '\$\(VCInstallDir\)bin\\ml\.exe') {
            $n.InnerText = $n.InnerText -replace '\$\(VCInstallDir\)bin\\ml\.exe', '$(VC_ExecutablePath_x86)\ml.exe'
        }
    }

    # public/tier0/memoverride.cpp hijacks the CRT allocator with VS2013-era
    # signatures (e.g. _calloc_base/_recalloc_base linkage, _CrtGetReportHook
    # macro form) that conflict with the modern UCRT shipped in VS2017+.
    # The file already supports a NO_MALLOC_OVERRIDE escape hatch; inject that
    # define for the client/server projects so the system allocator is used.
    $projName = [System.IO.Path]::GetFileNameWithoutExtension($proj.FullName)
    if ($projName -eq 'client_tf_mod' -or $projName -eq 'server_tf_mod') {
        $ppdNodes = $xml.SelectNodes('//m:ClCompile/m:PreprocessorDefinitions', $ns)
        foreach ($n in $ppdNodes) {
            if ($n.InnerText -notmatch 'NO_MALLOC_OVERRIDE') {
                $n.InnerText = 'NO_MALLOC_OVERRIDE;' + $n.InnerText
            }
        }

        # legacy_stdio_definitions.lib re-exposes the secure-suffix stdio
        # symbols (sscanf_s, sprintf_s, ...) that VS2015+ inlined in <stdio.h>
        # but that the prebuilt v120-era helper libs (dmxloader, etc.) still
        # reference at link time.
        # /FORCE:MULTIPLE: prebuilt particles.lib carries its own _hypot from
        # the legacy CRT, which clashes with libucrt.lib's _hypot. The library
        # version is binary-equivalent so we let the linker pick one.
        $linkNodes = $xml.SelectNodes('//m:Link', $ns)
        foreach ($ln in $linkNodes) {
            $deps = $ln.SelectSingleNode('m:AdditionalDependencies', $ns)
            if ($deps -and $deps.InnerText -notmatch 'legacy_stdio_definitions\.lib') {
                $deps.InnerText = 'legacy_stdio_definitions.lib;' + $deps.InnerText
            }
            $opts = $ln.SelectSingleNode('m:AdditionalOptions', $ns)
            if ($opts) {
                if ($opts.InnerText -notmatch '/FORCE:MULTIPLE') {
                    $opts.InnerText = $opts.InnerText.TrimEnd() + ' /FORCE:MULTIPLE'
                }
            } else {
                $opts = $xml.CreateElement('AdditionalOptions', $ns.LookupNamespace('m'))
                $opts.InnerText = '/FORCE:MULTIPLE'
                [void]$ln.AppendChild($opts)
            }
        }
    }

    $xml.Save($proj.FullName)
}

# Pre-flight: confirm the requested toolset is actually installed. VS2022 with
# only the IDE (no "Desktop development with C++" workload) ships MSBuild but
# not the v143 platform integration, which would silently fail per project.
$vsRoot = Find-VsInstallPath
$toolsetProps = if ($vsRoot) {
    Join-Path $vsRoot ("MSBuild\Microsoft\VC\v170\Platforms\Win32\PlatformToolsets\{0}\Toolset.props" -f $PlatformToolset)
} else { $null }
if (-not $toolsetProps -or -not (Test-Path -LiteralPath $toolsetProps)) {
    Write-Warning ("Platform toolset '$PlatformToolset' Win32 integration not found at:`n  $toolsetProps`n" +
                  "Install it via Visual Studio Installer:`n" +
                  "  ""C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe"" modify ``" + "`n" +
                  "    --installPath ""$vsRoot"" ``" + "`n" +
                  "    --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --quiet --norestart`n" +
                  "Skipping build. Prebuilt DLLs from the asset zips remain in dist\\.")
    exit 2
}

# Build dependency libs first, then the client + server dlls.
function Invoke-MsBuildProject {
    param([string]$ProjectPath)
    if (-not (Test-Path -LiteralPath $ProjectPath)) {
        Write-Warning "Project not found, skipping: $ProjectPath"
        return $false
    }
    Write-Section ("Building " + (Split-Path -Leaf $ProjectPath))
    & $msbuild $ProjectPath `
        /p:Configuration=$Configuration `
        /p:Platform=Win32 `
        /p:PlatformToolset=$PlatformToolset `
        /p:WindowsTargetPlatformVersion=$WindowsSdkVersion `
        /m /v:m /nologo 2>&1 | Out-Host
    $exit = $LASTEXITCODE
    return ($exit -eq 0)
}

$results = New-Object 'System.Collections.Generic.List[object]'
foreach ($rel in $AllProjects) {
    $full = Join-Path $SrcDir $rel
    $ok   = Invoke-MsBuildProject -ProjectPath $full
    $results.Add([pscustomobject]@{ Project = $rel; Ok = $ok })
    if (-not $ok -and ($LibProjects -contains $rel)) {
        Write-Warning "Dependency '$rel' failed; later projects that link against it will likely fail too."
    }
}

Write-Section "Build summary"
foreach ($r in $results) {
    $tag = if ($r.Ok) { 'OK    ' } else { 'FAILED' }
    Write-Host ("{0}  {1}" -f $tag, $r.Project)
}

$failed = ($results | Where-Object { -not $_.Ok }).Count
if ($failed -gt 0) {
    Write-Warning "$failed project(s) failed. Prebuilt DLLs from the asset zips remain in dist/ and the game stays playable."
    exit 1
}

if (-not $NoDeploy) {
    Write-Host "Build OK; copying outputs to dist/ via deploy.ps1"
    & "$PSScriptRoot\deploy.ps1"
}
