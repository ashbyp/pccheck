param(
    [string]$Version = "0.1.0",
    [string]$OutDir = ".\dist"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$stageName = "pccheck-release-$Version"
$stageDir = Join-Path $OutDir $stageName
$zipPath = Join-Path $OutDir "$stageName.zip"

Ensure-Directory -Path $OutDir
if (Test-Path -LiteralPath $stageDir) {
    Remove-Item -LiteralPath $stageDir -Recurse -Force
}
Ensure-Directory -Path $stageDir
Ensure-Directory -Path (Join-Path $stageDir "scripts")

$filesToCopy = @(
    "Run-PCDiagnostics-Fast.bat",
    "Run-PCDiagnostics.bat",
    "Run-PCDiagnostics-Full.bat",
    "README-USER.txt",
    "README.md"
)

foreach ($f in $filesToCopy) {
    $src = Join-Path $repoRoot $f
    if (-not (Test-Path -LiteralPath $src)) {
        throw "Missing required file: $src"
    }
    Copy-Item -LiteralPath $src -Destination (Join-Path $stageDir $f) -Force
}

$collectorSrc = Join-Path $repoRoot "scripts\Collect-PCDiagnostics.ps1"
if (-not (Test-Path -LiteralPath $collectorSrc)) {
    throw "Missing required file: $collectorSrc"
}
Copy-Item -LiteralPath $collectorSrc -Destination (Join-Path $stageDir "scripts\Collect-PCDiagnostics.ps1") -Force

if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Compress-Archive -Path $stageDir -DestinationPath $zipPath -Force

Write-Host "Release package created:"
Write-Host $zipPath
