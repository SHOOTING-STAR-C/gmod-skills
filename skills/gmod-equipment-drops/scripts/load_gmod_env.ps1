Set-StrictMode -Version Latest

function Expand-GmodEnvValues {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [switch]$AllowUnresolved
    )

    $pattern = '\$\{([A-Za-z_][A-Za-z0-9_]*)\}'
    $maxPasses = [Math]::Max(2, $Values.Count + 2)

    for ($pass = 0; $pass -lt $maxPasses; $pass++) {
        $changed = $false

        foreach ($name in @($Values.Keys)) {
            $current = [string]$Values[$name]
            $expanded = [regex]::Replace(
                $current,
                $pattern,
                {
                    param($match)
                    $referenceName = $match.Groups[1].Value
                    if ($Values.ContainsKey($referenceName)) {
                        [string]$Values[$referenceName]
                    } else {
                        $processValue = [Environment]::GetEnvironmentVariable(
                            $referenceName,
                            "Process"
                        )
                        if ($null -ne $processValue) {
                            $processValue
                        } else {
                            $match.Value
                        }
                    }
                }
            )

            if ($expanded -ne $current) {
                $Values[$name] = $expanded
                $changed = $true
            }
        }

        if (-not $changed) {
            break
        }
    }

    foreach ($name in @($Values.Keys)) {
        $unresolved = [regex]::Matches([string]$Values[$name], $pattern)
        if ($unresolved.Count -gt 0) {
            if ($AllowUnresolved) {
                continue
            }
            $references = @(
                $unresolved |
                    ForEach-Object { $_.Groups[1].Value } |
                    Select-Object -Unique
            )
            throw "Unresolved .env variable in ${name}: $($references -join ', ')"
        }
    }
}

function Set-GmodDerivedValue {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path
    )

    if (-not $Values.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace([string]$Values[$Name])) {
        $Values[$Name] = [System.IO.Path]::GetFullPath($Path)
    }
}

function Require-GmodEnvValue {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string[]]$Names
    )

    $missing = @(
        $Names | Where-Object {
            -not $Values.ContainsKey($_) -or [string]::IsNullOrWhiteSpace([string]$Values[$_])
        }
    )

    if ($missing.Count -gt 0) {
        throw "Missing required .env values: $($missing -join ', ')"
    }
}

function Import-GmodEnv {
    param(
        [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) ".env")
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Environment file not found: $Path. Copy .env.example to .env and configure it."
    }

    $values = @{}
    $lineNumber = 0

    foreach ($rawLine in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $lineNumber++
        $line = $rawLine.Trim()

        if ($line.Length -eq 0 -or $line.StartsWith("#")) {
            continue
        }

        $separatorIndex = $line.IndexOf("=")
        if ($separatorIndex -lt 1) {
            throw "Invalid .env entry at line ${lineNumber}: $rawLine"
        }

        $name = $line.Substring(0, $separatorIndex).Trim()
        $value = $line.Substring($separatorIndex + 1).Trim()

        if ($name -notmatch "^[A-Za-z_][A-Za-z0-9_]*$") {
            throw "Invalid .env variable name at line ${lineNumber}: $name"
        }

        if (
            $value.Length -ge 2 -and
            (($value.StartsWith('"') -and $value.EndsWith('"')) -or
             ($value.StartsWith("'") -and $value.EndsWith("'")))
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $values[$name] = $value
    }


    # Explicit values win; relative paths are anchored to the configuration file.
    $configRoot = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
    $skillRoot = Split-Path -Parent $PSScriptRoot
    $defaults = @{
        GMOD_SKILL_ROOT = $skillRoot
        GMOD_PYTHON_EXE = 'python'
    }
    foreach ($key in $defaults.Keys) {
        if (-not $values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key])) {
            $values[$key] = $defaults[$key]
        }
    }
    Expand-GmodEnvValues -Values $values
    foreach ($key in @($values.Keys)) {
        if (($key -match '(_DIR|_ROOT|_EXE)$') -and $values[$key] -and $key -ne 'GMOD_PYTHON_EXE') {
            $p = [string]$values[$key]
            if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $configRoot $p }
            $values[$key] = [System.IO.Path]::GetFullPath($p)
        }
    }
    function Set-ChildDefault([string]$Name, [string]$Parent, [string]$Child) {
        if ($values.ContainsKey($Parent) -and $values[$Parent]) {
            Set-GmodDerivedValue -Values $values -Name $Name -Path (Join-Path $values[$Parent] $Child)
        }
    }
    Set-ChildDefault 'GMOD_SKILL_ARTIFACTS_DIR' 'GMOD_SKILL_ROOT' 'artifacts'
    Set-ChildDefault 'GARRYSMOD_DIR' 'GMOD_ROOT' 'garrysmod'
    Set-ChildDefault 'GMOD_BIN_DIR' 'GMOD_ROOT' 'bin'
    Set-ChildDefault 'GMOD_ADDONS_DIR' 'GARRYSMOD_DIR' 'addons'
    Set-ChildDefault 'GMOD_BAKMOD_DIR' 'GARRYSMOD_DIR' 'bakmod'
    Set-ChildDefault 'GMOD_TOOLS_DIR' 'GMOD_BAKMOD_DIR' 'tools'
    Set-ChildDefault 'GMOD_WORK_DIR' 'GMOD_BAKMOD_DIR' 'work'
    Set-ChildDefault 'CROWBAR_DIR' 'GMOD_TOOLS_DIR' 'Crowbar'
    Set-ChildDefault 'CROWBAR_EXE' 'CROWBAR_DIR' 'Crowbar.exe'
    Set-ChildDefault 'CROWBAR_CLI_EXE' 'GMOD_TOOLS_DIR' 'CrowbarCLI.exe'
    Set-ChildDefault 'STUDIOMDL_EXE' 'GMOD_BIN_DIR' 'studiomdl.exe'
    Set-ChildDefault 'STUDIOMDL_CE_DIR' 'GMOD_TOOLS_DIR' 'StudioMDL-CE'
    Set-ChildDefault 'STUDIOMDL_CE_X64_EXE' 'STUDIOMDL_CE_DIR' 'x64/cestudiomdl.exe'
    Set-ChildDefault 'STUDIOMDL_CE_X86_EXE' 'STUDIOMDL_CE_DIR' 'x86/cestudiomdl.exe'
    foreach ($key in $values.Keys) {
        [Environment]::SetEnvironmentVariable($key, [string]$values[$key], 'Process')
    }
    return $values
}

function Get-GmodEnvValue {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$Default = ""
    )

    if ($Values.ContainsKey($Name) -and $Values[$Name]) {
        return $Values[$Name]
    }

    return $Default
}
