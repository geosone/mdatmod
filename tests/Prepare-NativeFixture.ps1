#Requires -Version 7.4
<#
.SYNOPSIS
Downloads a checksum-pinned native A49 installer into a disposable CI fixture.
.DESCRIPTION
Only a fresh directory is accepted. Vendor files are downloaded for testing and
never included in mdatmod archives. The native installer creates an offline
installation; no MIS service or network listener is started.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Directory,
    [ValidateSet('amd64', 'x86', 'x64')][string]$Architecture = 'amd64'
)
$ErrorActionPreference = 'Stop'
$profiles = @{
    amd64 = @{
        File = 'mys112a49_l64.rar'
        Hash = '16cabc63a2db23d88a376c4c68a1b618b5bcc3c3a25612b24d3828b1306a295c'
        Installer = 'bbf499b4ef6a371992acdfee86d033b4398a4fe1c730fa63ff28b37f29694a29'
    }
    x86 = @{
        File = 'mys112a49_w32.rar'
        Hash = '3cf9f4ee9ff47f93ffb25f287316fa32397e799e4469a50f9e77994109845e2c'
        Installer = 'd4211c4c187430191c962718d6a672775619ca48f4eb68987ce759303122e2b1'
    }
    x64 = @{
        File = 'mys112a49_w64.rar'
        Hash = '47e308ed03f2d2d69323c700102b3fd3e7e61588a0bf1df361dfbd9baa6f6255'
        Installer = 'a2318c91175f80e05fb59dce263a60fddede7d2d8c5fb771a3e18e20d433f6c6'
    }
}
if (($IsLinux -and $Architecture -ne 'amd64') -or ($IsWindows -and $Architecture -eq 'amd64')) {
    throw 'Select the matching native platform fixture.'
}
if (Test-Path -LiteralPath $Directory) {
    throw 'Choose a fresh fixture directory.'
}
$root = [IO.Path]::GetFullPath($Directory)
$vendor = Join-Path $root 'vendor'
$null = New-Item -ItemType Directory -Path $vendor
$profile = $profiles[$Architecture]
$archive = Join-Path $root $profile.File
Invoke-WebRequest -Uri ('https://mysticbbs.com/downloads/prealpha/' + $profile.File) -UserAgent 'Wget/1.25.0' -Headers @{Referer = 'https://mysticbbs.com/downloads/prealpha/'} -OutFile $archive
if ((Get-FileHash $archive).Hash -ine $profile.Hash) {
    throw 'Vendor archive checksum mismatch.'
}
if ($IsWindows) {
    & 7z x '-y' ('-o' + $vendor) $archive | Out-Null
} else {
    & unrar -x $archive ($vendor + '/') | Out-Null
}
if ($LASTEXITCODE) {
    throw 'Native installer extraction failed.'
}
$setupName = if ($IsWindows) {
    'install.exe'
} else {
    'install'
}
$setup = Join-Path $vendor $setupName
if ((Get-FileHash $setup).Hash -ine $profile.Installer) {
    throw 'Native installer checksum mismatch.'
}
if ($IsLinux) {
    & chmod 700 $setup
    if ($LASTEXITCODE) {
        throw 'Cannot set installer permissions.'
    }
}
$start = [Diagnostics.ProcessStartInfo]::new($setup)
$start.WorkingDirectory = $vendor
$start.UseShellExecute = $false
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.ArgumentList.Add('auto')
$start.ArgumentList.Add((Join-Path $root 'bbs'))
$process = [Diagnostics.Process]::Start($start)
try {
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    if (!$process.WaitForExit(120000)) {
        $process.Kill($true)
        throw 'Native installer timed out.'
    }
    if ($process.ExitCode) {
        throw 'Native installer failed.'
    }
} finally {
    $process.Dispose()
}
