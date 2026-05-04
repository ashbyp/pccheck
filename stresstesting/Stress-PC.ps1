param(
    [int]$DurationSeconds = 180,
    [int]$CpuWorkers = [Environment]::ProcessorCount,
    [double]$MemoryGB = 4,
    [switch]$EnableDiskIO,
    [switch]$Aggressive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Status {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

if ($DurationSeconds -lt 10) {
    throw "DurationSeconds must be at least 10."
}
if ($CpuWorkers -lt 1) {
    throw "CpuWorkers must be at least 1."
}
if ($MemoryGB -lt 0) {
    throw "MemoryGB cannot be negative."
}

if ($Aggressive) {
    $CpuWorkers = [Environment]::ProcessorCount
    if ($MemoryGB -lt 8) {
        $MemoryGB = 8
    }
    $EnableDiskIO = $true
}

$memBytes = [int64]($MemoryGB * 1GB)
$tempPath = Join-Path $env:TEMP "pc_stress_test.bin"
$jobs = @()

Write-Status "Starting stress test."
Write-Status "Duration: $DurationSeconds sec"
Write-Status "CPU workers: $CpuWorkers"
Write-Status "Memory target: $MemoryGB GB"
Write-Status "Disk I/O: $($EnableDiskIO.IsPresent)"
Write-Status "Temp file: $tempPath"

for ($i = 0; $i -lt $CpuWorkers; $i++) {
    $jobs += Start-Job -Name ("cpu_{0}" -f $i) -ScriptBlock {
        $x = 0.00001
        while ($true) {
            # Tight floating-point loop to keep a logical core busy.
            for ($j = 0; $j -lt 250000; $j++) {
                $x = [Math]::Sqrt($x + 1.23456789)
                if ($x -gt 10000) { $x = 0.00001 }
            }
        }
    }
}

if ($memBytes -gt 0) {
    $jobs += Start-Job -Name "mem_hog" -ScriptBlock {
        param([int64]$BytesToUse)
        $chunks = New-Object System.Collections.Generic.List[byte[]]
        $chunkSize = 64MB
        $allocated = 0L

        while ($allocated -lt $BytesToUse) {
            $size = [Math]::Min($chunkSize, ($BytesToUse - $allocated))
            $arr = New-Object byte[] $size
            # Touch pages so memory is committed.
            for ($k = 0; $k -lt $arr.Length; $k += 4096) {
                $arr[$k] = 1
            }
            $chunks.Add($arr) | Out-Null
            $allocated += $size
        }

        while ($true) {
            Start-Sleep -Milliseconds 200
        }
    } -ArgumentList $memBytes
}

if ($EnableDiskIO) {
    $jobs += Start-Job -Name "disk_io" -ScriptBlock {
        param([string]$FilePath)
        $rng = [Random]::new()
        $buffer = New-Object byte[] (4MB)
        while ($true) {
            $rng.NextBytes($buffer)
            [IO.File]::WriteAllBytes($FilePath, $buffer)
            [IO.File]::AppendAllText($FilePath, ("{0}`n" -f (Get-Date).ToString("o")))
        }
    } -ArgumentList $tempPath
}

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
try {
    while ($stopwatch.Elapsed.TotalSeconds -lt $DurationSeconds) {
        $left = [math]::Ceiling($DurationSeconds - $stopwatch.Elapsed.TotalSeconds)
        Write-Status ("Stress active. {0}s remaining..." -f $left)
        Start-Sleep -Seconds 5
    }
}
finally {
    Write-Status "Stopping jobs..."
    foreach ($job in $jobs) {
        try { Stop-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
        try { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch {}
    }
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }
    Write-Status "Stress test complete."
    Write-Status "Now run diagnostics immediately for best capture."
}
