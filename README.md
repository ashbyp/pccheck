# PC Performance Diagnostic Collector

This repo contains a PowerShell collector that captures a broad diagnostic bundle for later troubleshooting of Windows performance issues.

## Script

- `scripts/Collect-PCDiagnostics.ps1`
- `scripts/build-release.ps1`
- `Build-Release.bat` (double-click release packager)
- `Run-PCDiagnostics.bat` (double-click launcher, Quick mode)
- `Run-PCDiagnostics-Full.bat` (double-click launcher, Full mode)
- `Run-PCDiagnostics-Fast.bat` (double-click launcher, Fast mode / no burst sample)

## What it collects

- System/OS/hardware details
- CPU and memory snapshots (including top processes)
- Disk health and free-space pressure
- Network adapters and active connections snapshot
- Startup items, scheduled tasks, automatic services
- GPU/display and signed driver snapshot
- Windows update state and pending reboot checks
- Recent System/Application event log warnings/errors
- Crash artifact presence (WER archive/minidumps)
- Short burst time-series sample (CPU, disk queue, available memory)

## Output location

- Writes to Desktop as: `PCDiag_YYYYMMDD_HHMMSS`
- Creates:
  - `summary.md`
  - `manifest.json`
  - `raw\*.json` and `raw\*.txt`
  - `.zip` archive (unless `-NoZip`)

## Usage

```powershell
# Quick run (default)
powershell -ExecutionPolicy Bypass -File .\scripts\Collect-PCDiagnostics.ps1

# Full run (longer event lookback)
powershell -ExecutionPolicy Bypass -File .\scripts\Collect-PCDiagnostics.ps1 -Mode Full

# Increase burst sample duration
powershell -ExecutionPolicy Bypass -File .\scripts\Collect-PCDiagnostics.ps1 -BurstDurationSeconds 180 -BurstIntervalSeconds 2

# Redact user profile paths in output
powershell -ExecutionPolicy Bypass -File .\scripts\Collect-PCDiagnostics.ps1 -RedactUserPaths
```

Or just double-click:

- `Run-PCDiagnostics-Fast.bat` for Fast mode (no burst sample)
- `Run-PCDiagnostics.bat` for Quick mode
- `Run-PCDiagnostics-Full.bat` for Full mode

Expected runtime:

- Fast: typically under 2 minutes
- Quick: typically 1-3 minutes
- Full: typically 3-8 minutes

The console now prints `Collecting: ...` and `Done: ...` per step so you can see live progress.

## Notes

- The script is read-only in intent and does not change system configuration.
- Some probes may fail due to permissions; failures are logged in `summary.md` and `manifest.json`.
