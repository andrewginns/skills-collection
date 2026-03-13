[CmdletBinding()]
param(
    [string]$Json,
    [string]$JsonPath,
    [string]$ShareString,
    [string]$ShareStringPath,
    [string]$Registry,
    [switch]$PortableOnly,
    [switch]$SelfTest,
    [string]$PythonVersion = "3.12"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-UsableCommand {
    param([string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        return $null
    }
    if ($command.Source -and $command.Source -like "*WindowsApps*") {
        return $null
    }
    return $command.Source
}

if ($Json -and $JsonPath) {
    throw "Use either -Json or -JsonPath, not both."
}
if ($ShareString -and $ShareStringPath) {
    throw "Use either -ShareString or -ShareStringPath, not both."
}
if (($Json -or $JsonPath) -and ($ShareString -or $ShareStringPath)) {
    throw "Use either JSON input or a share string, not both."
}

$stdinContent = $null
if ($MyInvocation.ExpectingInput) {
    $stdinContent = [string]::Join([Environment]::NewLine, @($input))
    if ($stdinContent.Length -eq 0) {
        $stdinContent = $null
    }
}

$scriptPath = Join-Path $PSScriptRoot "encode_codex_theme.py"
$runner = @()

$python = Get-UsableCommand "python"
if ($python) {
    $runner = @($python)
} else {
    $python3 = Get-UsableCommand "python3"
    if ($python3) {
        $runner = @($python3)
    } else {
        $py = Get-Command py -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($py) {
            $runner = @($py.Source, "-3")
        } else {
            $uv = Get-Command uv -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($uv) {
                $runner = @($uv.Source, "run", "--python", $PythonVersion)
            }
        }
    }
}

if ($runner.Count -eq 0) {
    throw "No usable Python runtime was found. Install Python or uv, or call encode_codex_theme.py with a working interpreter."
}

$command = @()
$command += $runner
$command += $scriptPath

if ($Registry) {
    $command += @("--registry", $Registry)
}
if ($PortableOnly) {
    $command += "--portable-only"
}
if ($SelfTest) {
    $command += "--self-test"
}
if ($ShareStringPath) {
    $command += @("--share-string-file", $ShareStringPath)
} elseif ($ShareString) {
    $command += @("--share-string", $ShareString)
} elseif ($JsonPath) {
    $command += @("--json-file", $JsonPath)
} elseif ($Json) {
    $command += @("--json", $Json)
}

$exe = $command[0]
$exeArgs = @()
if ($command.Count -gt 1) {
    $exeArgs = @($command[1..($command.Count - 1)])
}

if ($stdinContent -ne $null -and -not $Json -and -not $ShareString) {
    $stdinContent | & $exe @exeArgs
} else {
    & $exe @exeArgs
}

exit $LASTEXITCODE
