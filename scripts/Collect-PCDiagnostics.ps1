param(
    [ValidateSet("Quick", "Full")]
    [string]$Mode = "Quick",
    [int]$BurstDurationSeconds = 30,
    [int]$BurstIntervalSeconds = 2,
    [switch]$RedactUserPaths,
    [switch]$NoZip
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Status {
    param([string]$Message)
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Ensure-Directory {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Safe-Name {
    param([Parameter(Mandatory = $true)][string]$Name)
    return ($Name -replace '[\\/:*?"<>|]', "_")
}

function Redact-Text {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$UserProfile
    )
    $escaped = [Regex]::Escape($UserProfile)
    return [Regex]::Replace($Text, $escaped, "%USERPROFILE%", [Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Save-Json {
    param(
        [Parameter(Mandatory = $true)]$Data,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 6
    )
    $json = $Data | ConvertTo-Json -Depth $Depth
    if ($RedactUserPaths) {
        $json = Redact-Text -Text $json -UserProfile $env:USERPROFILE
    }
    [IO.File]::WriteAllText($Path, $json, [Text.UTF8Encoding]::new($false))
}

function Save-Text {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Path
    )
    if ($RedactUserPaths) {
        $Text = Redact-Text -Text $Text -UserProfile $env:USERPROFILE
    }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Invoke-Capture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Script,
        [Parameter(Mandatory = $true)][string]$OutDir,
        [Parameter(Mandatory = $true)][System.Collections.IList]$Manifest
    )

    $start = Get-Date
    $safeBase = Safe-Name -Name $Name
    $jsonPath = Join-Path $OutDir "$safeBase.json"
    $txtPath = Join-Path $OutDir "$safeBase.txt"

    Write-Status "Collecting: $Name"
    try {
        $result = & $Script
        $hasResult = $null -ne $result

        if ($hasResult) {
            Save-Json -Data $result -Path $jsonPath
            $text = ($result | Out-String)
            Save-Text -Text $text -Path $txtPath
        } else {
            Save-Text -Text "No data returned." -Path $txtPath
        }

        $Manifest.Add([pscustomobject]@{
            name = $Name
            status = "ok"
            started = $start.ToString("o")
            ended = (Get-Date).ToString("o")
            files = @(
                if (Test-Path -LiteralPath $jsonPath) { Split-Path -Leaf $jsonPath }
                if (Test-Path -LiteralPath $txtPath) { Split-Path -Leaf $txtPath }
            )
            error = $null
        }) | Out-Null
        Write-Status "Done: $Name"
    } catch {
        $err = $_.Exception.Message
        Save-Text -Text "Capture failed: $err" -Path $txtPath
        $Manifest.Add([pscustomobject]@{
            name = $Name
            status = "error"
            started = $start.ToString("o")
            ended = (Get-Date).ToString("o")
            files = @((Split-Path -Leaf $txtPath))
            error = $err
        }) | Out-Null
        Write-Status "Failed: $Name"
    }
}

function Get-TopCpuProcessSummary {
    try {
        $samples = Get-Counter '\Process(*)\% Processor Time' -SampleInterval 1 -MaxSamples 2
        $counters = $samples.CounterSamples |
            Where-Object { $_.Path -notlike "*_Total*" -and $_.Path -notlike "*Idle*" } |
            ForEach-Object {
                [pscustomobject]@{
                    instance = $_.InstanceName
                    cpu = [math]::Round($_.CookedValue / [Environment]::ProcessorCount, 2)
                }
            } |
            Sort-Object cpu -Descending |
            Select-Object -First 10
        return $counters
    } catch {
        return @()
    }
}

function Get-EventHighlights {
    param([datetime]$StartTime)
    try {
        $system = Get-WinEvent -FilterHashtable @{
            LogName = "System"
            Level = @(1, 2, 3)
            StartTime = $StartTime
        } -ErrorAction SilentlyContinue

        $application = Get-WinEvent -FilterHashtable @{
            LogName = "Application"
            Level = @(1, 2, 3)
            StartTime = $StartTime
        } -ErrorAction SilentlyContinue
    } catch {
        $system = @()
        $application = @()
    }

    [pscustomobject]@{
        systemErrorsWarnings = ($system | Measure-Object).Count
        applicationErrorsWarnings = ($application | Measure-Object).Count
        topSystemProviders = $system | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 8 Name, Count
        topApplicationProviders = $application | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 8 Name, Count
    }
}

function Get-DiskPressure {
    try {
        $logical = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" | Select-Object DeviceID, VolumeName, @{n="SizeGB";e={[math]::Round($_.Size/1GB,2)}}, @{n="FreeGB";e={[math]::Round($_.FreeSpace/1GB,2)}}, @{n="FreePct";e={if($_.Size -gt 0){[math]::Round(($_.FreeSpace/$_.Size)*100,2)} else {0}}}
        $low = $logical | Where-Object { $_.FreePct -lt 15 }
        [pscustomobject]@{
            disks = $logical
            lowFreeDisks = $low
        }
    } catch {
        [pscustomobject]@{
            disks = @()
            lowFreeDisks = @()
        }
    }
}

function Get-MemoryPressure {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedGB = [math]::Round($totalGB - $freeGB, 2)
        $usedPct = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 2) } else { 0 }
        [pscustomobject]@{
            totalGB = $totalGB
            usedGB = $usedGB
            freeGB = $freeGB
            usedPct = $usedPct
        }
    } catch {
        [pscustomobject]@{
            totalGB = 0
            usedGB = 0
            freeGB = 0
            usedPct = 0
        }
    }
}

function Get-TopProcessSnapshot {
    param([int]$MaxCount = 20)
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
        try {
            $cpuSeconds = 0
            if ($null -ne $p.TotalProcessorTime) {
                $cpuSeconds = [math]::Round($p.TotalProcessorTime.TotalSeconds, 2)
            }
            $startTime = $null
            try { $startTime = $p.StartTime } catch { $startTime = $null }
            $items.Add([pscustomobject]@{
                Name = $p.ProcessName
                Id = $p.Id
                CPUSeconds = $cpuSeconds
                WorkingSetMB = [math]::Round($p.WorkingSet64 / 1MB, 2)
                PrivateMemoryMB = [math]::Round($p.PrivateMemorySize64 / 1MB, 2)
                StartTime = $startTime
            }) | Out-Null
        } catch {
            continue
        }
    }
    $items | Sort-Object CPUSeconds -Descending | Select-Object -First $MaxCount
}

function Get-ProcessAttribution {
    param([int]$MaxCount = 200)

    try {
        $procMap = @{}
        foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
            $procMap[[int]$p.Id] = $p
        }

        $cimProcs = Get-CimInstance Win32_Process -ErrorAction Stop
        $items = New-Object System.Collections.Generic.List[object]

        foreach ($cp in $cimProcs) {
            $pid = [int]$cp.ProcessId
            $cpuSeconds = $null
            $wsMB = $null
            $pmMB = $null
            $startTime = $null

            if ($procMap.ContainsKey($pid)) {
                $pp = $procMap[$pid]
                try {
                    if ($null -ne $pp.TotalProcessorTime) {
                        $cpuSeconds = [math]::Round($pp.TotalProcessorTime.TotalSeconds, 2)
                    }
                } catch {}
                try { $wsMB = [math]::Round($pp.WorkingSet64 / 1MB, 2) } catch {}
                try { $pmMB = [math]::Round($pp.PrivateMemorySize64 / 1MB, 2) } catch {}
                try { $startTime = $pp.StartTime } catch {}
            }

            $items.Add([pscustomobject]@{
                Name = $cp.Name
                Id = $pid
                ParentProcessId = [int]$cp.ParentProcessId
                CommandLine = $cp.CommandLine
                ExecutablePath = $cp.ExecutablePath
                CPUSeconds = $cpuSeconds
                WorkingSetMB = $wsMB
                PrivateMemoryMB = $pmMB
                StartTime = $startTime
            }) | Out-Null
        }

        $items |
            Sort-Object @{Expression = { if ($null -eq $_.CPUSeconds) { -1 } else { $_.CPUSeconds } }; Descending = $true} |
            Select-Object -First $MaxCount
    } catch {
        @()
    }
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$desktopPath = [Environment]::GetFolderPath("Desktop")
$rootName = "PCDiag_{0}" -f $timestamp
$rootOutDir = Join-Path $desktopPath $rootName
$rawDir = Join-Path $rootOutDir "raw"

try {
    Ensure-Directory -Path $rootOutDir
    Ensure-Directory -Path $rawDir
} catch {
    $fallbackRoot = Join-Path (Get-Location).Path $rootName
    Write-Warning "Desktop path is not writable. Falling back to: $fallbackRoot"
    $rootOutDir = $fallbackRoot
    $rawDir = Join-Path $rootOutDir "raw"
    Ensure-Directory -Path $rootOutDir
    Ensure-Directory -Path $rawDir
}

Write-Status "Output directory: $rootOutDir"

$manifest = [System.Collections.Generic.List[object]]::new()
$runStart = Get-Date
$eventLookbackHours = if ($Mode -eq "Full") { 72 } else { 24 }
$eventStart = (Get-Date).AddHours(-$eventLookbackHours)
$isFull = $Mode -eq "Full"
$maxEventRows = if ($isFull) { 1000 } else { 300 }

if ($isFull) {
    Invoke-Capture -Name "computer_info" -OutDir $rawDir -Manifest $manifest -Script {
        Get-ComputerInfo
    }
}

Invoke-Capture -Name "os_and_uptime" -OutDir $rawDir -Manifest $manifest -Script {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    [pscustomobject]@{
        computerName = $env:COMPUTERNAME
        osCaption = $os.Caption
        version = $os.Version
        buildNumber = $os.BuildNumber
        lastBootUpTime = $os.LastBootUpTime
        uptimeHours = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 2)
        manufacturer = $cs.Manufacturer
        model = $cs.Model
        totalPhysicalMemoryGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    }
}

Invoke-Capture -Name "cpu_memory_snapshot" -OutDir $rawDir -Manifest $manifest -Script {
    $proc = Get-TopProcessSnapshot -MaxCount 20
    [pscustomobject]@{
        memory = Get-MemoryPressure
        topCpuProcesses = $proc
        topCpuLiveCounter = Get-TopCpuProcessSummary
        processAttribution = Get-ProcessAttribution -MaxCount 300
        processor = Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
    }
}

Invoke-Capture -Name "disk_snapshot" -OutDir $rawDir -Manifest $manifest -Script {
    $physical = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, Size
    [pscustomobject]@{
        pressure = Get-DiskPressure
        physicalDisks = $physical
    }
}

Invoke-Capture -Name "network_snapshot" -OutDir $rawDir -Manifest $manifest -Script {
    [pscustomobject]@{
        adapters = Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress
        ipconfig = (ipconfig /all | Out-String)
        tcpConnections = Get-NetTCPConnection -State Established | Select-Object -First 200 LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess, State
    }
}

Invoke-Capture -Name "startup_and_tasks" -OutDir $rawDir -Manifest $manifest -Script {
    $scheduled = if ($isFull) {
        Get-ScheduledTask | Select-Object TaskName, TaskPath, State, Author
    } else {
        Get-ScheduledTask | Select-Object -First 200 TaskName, TaskPath, State, Author
    }
    [pscustomobject]@{
        startupCommands = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location, User
        scheduledTasks = $scheduled
        servicesAuto = Get-Service | Where-Object { $_.StartType -eq "Automatic" } | Select-Object Name, DisplayName, Status, StartType
    }
}

Invoke-Capture -Name "drivers_and_gpu" -OutDir $rawDir -Manifest $manifest -Script {
    [pscustomobject]@{
        display = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate, AdapterRAM, Status
        pnpSignedDrivers = Get-CimInstance Win32_PnPSignedDriver | Select-Object -First 500 DeviceName, DriverVersion, DriverDate, Manufacturer, IsSigned
    }
}

Invoke-Capture -Name "windows_update_status" -OutDir $rawDir -Manifest $manifest -Script {
    $rebootPending = $false
    $pendingPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($p in $pendingPaths) {
        if (Test-Path $p) { $rebootPending = $true }
    }
    [pscustomobject]@{
        hotfixes = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 50 HotFixID, InstalledOn, Description
        rebootPending = $rebootPending
    }
}

Invoke-Capture -Name "event_log_highlights" -OutDir $rawDir -Manifest $manifest -Script {
    Get-EventHighlights -StartTime $eventStart
}

Invoke-Capture -Name "event_log_system_recent" -OutDir $rawDir -Manifest $manifest -Script {
    Get-WinEvent -FilterHashtable @{
        LogName = "System"
        Level = @(1, 2, 3)
        StartTime = $eventStart
    } -ErrorAction SilentlyContinue | Select-Object -First $maxEventRows TimeCreated, Id, LevelDisplayName, ProviderName, Message
}

Invoke-Capture -Name "event_log_application_recent" -OutDir $rawDir -Manifest $manifest -Script {
    Get-WinEvent -FilterHashtable @{
        LogName = "Application"
        Level = @(1, 2, 3)
        StartTime = $eventStart
    } -ErrorAction SilentlyContinue | Select-Object -First $maxEventRows TimeCreated, Id, LevelDisplayName, ProviderName, Message
}

Invoke-Capture -Name "crash_artifacts" -OutDir $rawDir -Manifest $manifest -Script {
    $werPath = Join-Path $env:ProgramData "Microsoft\Windows\WER\ReportArchive"
    $miniDumpPath = Join-Path $env:SystemRoot "Minidump"
    [pscustomobject]@{
        werExists = Test-Path -LiteralPath $werPath
        minidumpExists = Test-Path -LiteralPath $miniDumpPath
        recentWerFolders = if (Test-Path -LiteralPath $werPath) { Get-ChildItem -Path $werPath -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 20 Name, LastWriteTime } else { @() }
        recentMinidumps = if (Test-Path -LiteralPath $miniDumpPath) { Get-ChildItem -Path $miniDumpPath -File | Sort-Object LastWriteTime -Descending | Select-Object -First 20 Name, Length, LastWriteTime } else { @() }
    }
}

if ($BurstDurationSeconds -gt 0 -and $BurstIntervalSeconds -gt 0) {
    Invoke-Capture -Name "burst_timeseries" -OutDir $rawDir -Manifest $manifest -Script {
        $samples = New-Object System.Collections.Generic.List[object]
        $sampleCount = [math]::Ceiling($BurstDurationSeconds / $BurstIntervalSeconds)
        for ($i = 0; $i -lt $sampleCount; $i++) {
            $cpu = (Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples[0].CookedValue
            $diskQueue = (Get-Counter '\PhysicalDisk(_Total)\Current Disk Queue Length').CounterSamples[0].CookedValue
            $availMB = (Get-Counter '\Memory\Available MBytes').CounterSamples[0].CookedValue
            $samples.Add([pscustomobject]@{
                timestamp = (Get-Date).ToString("o")
                cpuTotalPct = [math]::Round($cpu, 2)
                diskQueueLength = [math]::Round($diskQueue, 2)
                availableMemoryMB = [math]::Round($availMB, 2)
            }) | Out-Null
            Start-Sleep -Seconds $BurstIntervalSeconds
        }
        $samples
    }
}

$manifestPath = Join-Path $rootOutDir "manifest.json"
Save-Json -Data ([pscustomobject]@{
    tool = "PCDiag Collector"
    version = "0.1.0"
    mode = $Mode
    redacted = [bool]$RedactUserPaths
    burstDurationSeconds = $BurstDurationSeconds
    burstIntervalSeconds = $BurstIntervalSeconds
    startedAt = $runStart.ToString("o")
    endedAt = (Get-Date).ToString("o")
    artifacts = $manifest
}) -Path $manifestPath -Depth 8

$summaryPath = Join-Path $rootOutDir "summary.md"
$memory = Get-MemoryPressure
$disk = Get-DiskPressure
$eventHighlights = Get-EventHighlights -StartTime $eventStart
$topLive = Get-TopCpuProcessSummary

$lowDiskLines = if (($disk.lowFreeDisks | Measure-Object).Count -gt 0) {
    ($disk.lowFreeDisks | ForEach-Object { "- $($_.DeviceID): $($_.FreeGB) GB free ($($_.FreePct)%)" }) -join "`n"
} else {
    "- None"
}

$topCpuLines = if (($topLive | Measure-Object).Count -gt 0) {
    ($topLive | ForEach-Object { "- $($_.instance): $($_.cpu)% (normalized per logical CPU)" }) -join "`n"
} else {
    "- No samples"
}

$errorArtifacts = $manifest | Where-Object { $_.status -eq "error" }
$errorLines = if (($errorArtifacts | Measure-Object).Count -gt 0) {
    ($errorArtifacts | ForEach-Object { "- $($_.name): $($_.error)" }) -join "`n"
} else {
    "- None"
}

$summary = @"
# PC Diagnostic Summary

- Run time (UTC): $((Get-Date).ToUniversalTime().ToString("u"))
- Mode: $Mode
- Output folder: $rootOutDir
- Event log lookback hours: $eventLookbackHours

## Quick Signals

- Memory used: $($memory.usedGB) GB / $($memory.totalGB) GB ($($memory.usedPct)%)
- System event warnings/errors (last $eventLookbackHours h): $($eventHighlights.systemErrorsWarnings)
- Application event warnings/errors (last $eventLookbackHours h): $($eventHighlights.applicationErrorsWarnings)

## Potential Issues

### Low Disk Free Space (<15%)
$lowDiskLines

### Top CPU Consumers (live sample)
$topCpuLines

### Collection Errors
$errorLines

## Next Analysis Steps

- Correlate timestamps from `burst_timeseries` with System/Application errors.
- Inspect top providers in `event_log_highlights`.
- Review startup load from `startup_and_tasks`.
- Check `crash_artifacts` for recurring WER/minidump patterns.
"@

Save-Text -Text $summary -Path $summaryPath

if (-not $NoZip) {
    $zipPath = "$rootOutDir.zip"
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path $rootOutDir -DestinationPath $zipPath -Force
}

Write-Status "Complete."
Write-Status "Summary: $summaryPath"
if (-not $NoZip) {
    Write-Status "Archive: $rootOutDir.zip"
}
