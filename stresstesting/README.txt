Stress Testing Harness
======================

Purpose
- Intentionally create CPU/memory/disk pressure so you can verify the diagnostics collector detects issues.

Files
- Stress-PC.ps1
- Run-StressTest.bat

Quick start
1) Run as Administrator if possible.
2) Double-click Run-StressTest.bat
3) While stress is active, run your diagnostics collector.

Recommended test flow
1) Baseline run:
   - Run diagnostics normally (no stress), save output.
2) Stress run:
   - Start stress test for 3-5 minutes.
   - Start diagnostics during stress (or immediately after).
3) Compare runs:
   - Check CPU peaks, memory pressure, service timeouts, app hangs, and event volume.

PowerShell examples
- Moderate:
  powershell -ExecutionPolicy Bypass -File .\stresstesting\Stress-PC.ps1 -DurationSeconds 180 -CpuWorkers 4 -MemoryGB 4 -EnableDiskIO

- CPU-heavy:
  powershell -ExecutionPolicy Bypass -File .\stresstesting\Stress-PC.ps1 -DurationSeconds 180 -CpuWorkers 8 -MemoryGB 2

- Aggressive (use carefully):
  powershell -ExecutionPolicy Bypass -File .\stresstesting\Stress-PC.ps1 -DurationSeconds 240 -Aggressive

Notes
- This script is expected to make the machine feel slow.
- It should stop itself when duration ends.
- If interrupted, rerun PowerShell and close leftover jobs:
  Get-Job | Stop-Job -Force; Get-Job | Remove-Job -Force
