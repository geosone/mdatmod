#Requires -Version 7.4
<#
.SYNOPSIS
Builds and self-tests the native Windows executable with a pinned Lazarus/FPC.
.DESCRIPTION
Requires a native Windows compiler for the selected target and refuses a PE
machine type that does not match it. The output directory must be fresh; the
caller packages the executable with packaging/README.txt.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LazarusDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateSet('x86', 'x64')][string]$Architecture = 'x64'
)
$ErrorActionPreference = 'Stop'
if (!$IsWindows) {
    throw 'Use a native Windows Lazarus/FPC installation.'
}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$target = if ($Architecture -eq 'x64') {
    'x86_64-win64'
} else {
    'i386-win32'
}
$compiler = Join-Path $LazarusDirectory "fpc/3.2.2/bin/$target/fpc.exe"
if (!(Test-Path -LiteralPath $compiler)) {
    throw "Missing native compiler for $target."
}
if (Test-Path -LiteralPath $OutputDirectory) {
    throw 'Choose a fresh output directory.'
}
$output = [IO.Path]::GetFullPath($OutputDirectory)
$units = Join-Path $output 'units'
$null = New-Item -ItemType Directory -Path $units -Force
$exe = Join-Path $output 'mdatmod.exe'
$arguments = @(
    '-MObjFPC', '-Scghi', '-O2', '-g-',
    ('-Fu' + (Join-Path $root 'src')),
    ('-FU' + $units), ('-o' + $exe), (Join-Path $root 'src/mdatmod.lpr')
)
& $compiler @arguments
if ($LASTEXITCODE) {
    throw 'Free Pascal compilation failed.'
}
# Verify PE machine type so an incorrectly selected compiler cannot be mislabeled.
$bytes = [IO.File]::ReadAllBytes($exe)
$header = [BitConverter]::ToInt32($bytes, 0x3c)
$machine = [BitConverter]::ToUInt16($bytes, $header + 4)
$expectedMachine = if ($Architecture -eq 'x64') {
    0x8664
} else {
    0x14c
}
if ($machine -ne $expectedMachine) {
    throw 'Executable architecture does not match the package target.'
}
& $exe --self-test
if ($LASTEXITCODE) {
    throw 'Native self-test failed.'
}
$hash = (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS'), "$hash  mdatmod.exe`n")
[pscustomobject]@{
    Executable   = $exe
    Architecture = $Architecture
    SHA256       = $hash
}
