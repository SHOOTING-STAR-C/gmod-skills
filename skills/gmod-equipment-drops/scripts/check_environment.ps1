[CmdletBinding()]
param(
    [string]$EnvFile = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env'),
    [ValidateSet('lua','scan','decompile','compile','model')][string]$Task = 'lua',
    [string]$AddonRoot,
    [ValidateSet('ce-x64','stock')][string]$Compiler = 'ce-x64',
    [switch]$RequireBlender
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'load_gmod_env.ps1')
$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check($Name, $Passed, $Detail) {
    $checks.Add([pscustomobject]@{name=$Name; passed=[bool]$Passed; detail=[string]$Detail})
}
function Check-PathValue($Name, $Kind) {
    $value = if ($config.ContainsKey($Name)) { [string]$config[$Name] } else { '' }
    $ok = $value -and (Test-Path -LiteralPath $value -PathType $Kind)
    Add-Check $Name $ok $(if ($value) { $value } else { 'Not configured' })
}
try {
    $config = Import-GmodEnv -Path $EnvFile
    if (-not $AddonRoot -and $config.ContainsKey('GMOD_ADDON_DIR')) { $AddonRoot = $config['GMOD_ADDON_DIR'] }
    Add-Check 'addon_root' ($AddonRoot -and (Test-Path -LiteralPath $AddonRoot -PathType Container)) $AddonRoot
    if ($AddonRoot -and (Test-Path -LiteralPath $AddonRoot -PathType Container)) {
        $markers = @('lua','models','addon.json') | Where-Object { Test-Path -LiteralPath (Join-Path $AddonRoot $_) }
        Add-Check 'addon_layout' (@($markers).Count -gt 0) 'Expected lua/, models/ or addon.json; does not prove target identity'
    }
    if ($Task -eq 'scan') {
        $python = [string]$config['GMOD_PYTHON_EXE']
        try {
            $version = & $python -c 'import sys; print(sys.version.split()[0]); sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>&1
            Add-Check 'python_3.9+' ($LASTEXITCODE -eq 0) ($version -join ' ')
        } catch { Add-Check 'python_3.9+' $false $_.Exception.Message }
    }
    if ($Task -in @('decompile','model')) { Check-PathValue 'CROWBAR_CLI_EXE' 'Leaf' }
    if ($Task -in @('compile','model')) {
        Check-PathValue 'GARRYSMOD_DIR' 'Container'
        Check-PathValue $(if ($Compiler -eq 'stock') { 'STUDIOMDL_EXE' } else { 'STUDIOMDL_CE_X64_EXE' }) 'Leaf'
    }
    if ($RequireBlender) { Check-PathValue 'BLENDER_EXE' 'Leaf' }
} catch { Add-Check 'configuration' $false $_.Exception.Message }
$failed = @($checks | Where-Object { -not $_.passed }).Count
[pscustomobject]@{
    task=$Task; status=$(if ($failed) { 'fail' } else { 'pass' }); checks=@($checks.ToArray())
    scope='Configuration and task prerequisites only. Tool file presence does not prove launch, version compatibility, model validity or game behavior.'
    game_tested=$false
} | ConvertTo-Json -Depth 6
if ($failed) { exit 1 }
exit 0
