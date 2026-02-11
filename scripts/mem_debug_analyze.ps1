<#
.SYNOPSIS
    FluxDown Memory Debug - Step 2: Query memory usage
.USAGE
    .\scripts\mem_debug_analyze.ps1 [-GC] [-Loop] [-IntervalSec 5] [-DurationSec 60] [-TopN 20]
#>
param(
    [switch]$GC,
    [switch]$Loop,
    [int]$IntervalSec = 5,
    [int]$DurationSec = 60,
    [int]$TopN = 20
)

$ErrorActionPreference = "Stop"
$OutputDir = Join-Path (Join-Path $PSScriptRoot "..") ".mem_debug"
$UrlFile = Join-Path $OutputDir "vm_service_url.txt"

if (-not (Test-Path $UrlFile)) {
    Write-Host "[mem_debug] VM Service URL file not found" -ForegroundColor Red
    Write-Host "[mem_debug] Run first: .\scripts\mem_debug_launch.ps1" -ForegroundColor Yellow
    exit 1
}

$vmUrl = ((Get-Content $UrlFile -Raw) -replace '[\r\n]', '').Trim()
if (-not $vmUrl.EndsWith('/')) { $vmUrl = $vmUrl + '/' }
$script:baseUrl = $vmUrl

Write-Host "[mem_debug] VM Service: $($script:baseUrl)" -ForegroundColor Cyan

function Invoke-VmService {
    param([string]$Method, [hashtable]$Params = @{})
    $url = $script:baseUrl + $Method
    if ($Params.Count -gt 0) {
        $qp = ($Params.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
        $url = $url + "?" + $qp
    }
    try {
        return Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10
    }
    catch {
        Write-Host "[mem_debug] HTTP error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Get-AppProcessMemory {
    param([int]$AppPid)
    try {
        $proc = Get-Process -Id $AppPid -ErrorAction Stop
        return @{
            WorkingSet64MB   = [math]::Round($proc.WorkingSet64 / 1MB, 2)
            PrivateMemoryMB  = [math]::Round($proc.PrivateMemorySize64 / 1MB, 2)
            VirtualMemoryMB  = [math]::Round($proc.VirtualMemorySize64 / 1MB, 2)
            PeakWorkingSetMB = [math]::Round($proc.PeakWorkingSet64 / 1MB, 2)
        }
    }
    catch { return $null }
}

function Collect-MemorySnapshot {
    param([bool]$ShowTopClasses = $false)
    $ts = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    Write-Host "" -NoNewline
    Write-Host "[$ts] Collecting memory data..." -ForegroundColor Cyan

    $vm = Invoke-VmService -Method "getVM"
    if (-not $vm -or -not $vm.result) {
        Write-Host "[mem_debug] Cannot connect to VM Service" -ForegroundColor Red
        return $null
    }

    $vmr = $vm.result
    $appPid = $vmr.pid
    $curRSS = [math]::Round($vmr._currentRSS / 1MB, 2)
    $maxRSS = [math]::Round($vmr._maxRSS / 1MB, 2)
    $curMem = [math]::Round($vmr._currentMemory / 1MB, 2)

    Write-Host "  VM: PID=$appPid  RSS=$curRSS MB (peak $maxRSS MB)  Mem=$curMem MB" -ForegroundColor Gray

    $report = @{
        timestamp     = $ts
        vm            = @{ pid = $appPid; currentRSS_MB = $curRSS; maxRSS_MB = $maxRSS; currentMem_MB = $curMem }
        isolates      = @()
        processMemory = Get-AppProcessMemory -AppPid $appPid
        topClasses    = @()
    }

    $isolates = $vmr.isolates
    if ($isolates) {
        foreach ($isolate in $isolates) {
            $isoId = $isolate.id
            $isoName = $isolate.name
            $gcParam = if ($GC) { "true" } else { "false" }
            $ap = Invoke-VmService -Method "getAllocationProfile" -Params @{ isolateId = $isoId; gc = $gcParam }

            if ($ap -and $ap.result -and $ap.result.memoryUsage) {
                $mu = $ap.result.memoryUsage
                $heapUsed = [math]::Round($mu.heapUsage / 1MB, 2)
                $heapCap  = [math]::Round($mu.heapCapacity / 1MB, 2)
                $ext      = [math]::Round($mu.externalUsage / 1MB, 2)

                Write-Host "  Isolate [$isoName]: Heap=$heapUsed/$heapCap MB  External=$ext MB" -ForegroundColor White

                $isoData = @{
                    id = $isoId; name = $isoName
                    heapUsedMB = $heapUsed; heapCapacityMB = $heapCap; externalMB = $ext
                    heapUsedBytes = $mu.heapUsage; heapCapacityBytes = $mu.heapCapacity; externalBytes = $mu.externalUsage
                }
                $report.isolates += $isoData

                if ($ShowTopClasses -and $ap.result.members) {
                    $top = $ap.result.members |
                        Where-Object { $_.bytesCurrent -gt 0 } |
                        Sort-Object { $_.bytesCurrent } -Descending |
                        Select-Object -First $TopN

                    Write-Host ""
                    Write-Host ("    {0,-45} {1,10} {2,10}" -f "Class", "Instances", "KB") -ForegroundColor DarkYellow
                    Write-Host "    $('-' * 67)" -ForegroundColor DarkGray

                    $topList = @()
                    foreach ($m in $top) {
                        $cn = ""
                        if ($m.class -is [string]) {
                            $rx = [regex]::Match($m.class, 'name=([^;]+)')
                            if ($rx.Success) { $cn = $rx.Groups[1].Value } else { $cn = $m.class }
                        } elseif ($m.class.name) { $cn = $m.class.name }
                        else { $cn = "$($m.class)" }
                        $kb = [math]::Round($m.bytesCurrent / 1KB, 1)
                        Write-Host ("    {0,-45} {1,10} {2,10}" -f $cn, $m.instancesCurrent, $kb) -ForegroundColor White
                        $topList += @{ class = $cn; instances = $m.instancesCurrent; bytesKB = $kb }
                    }
                    $report.topClasses = $topList
                }
            } else {
                Write-Host "  Isolate [$isoName]: No heap data available" -ForegroundColor Yellow
            }
        }
    }

    $pm = $report.processMemory
    if ($pm) {
        Write-Host "  Process: WorkingSet=$($pm.WorkingSet64MB) MB  Private=$($pm.PrivateMemoryMB) MB  Peak=$($pm.PeakWorkingSetMB) MB" -ForegroundColor Gray
    }
    return $report
}

# === Main ===
if ($Loop) {
    Write-Host "[mem_debug] Loop mode: interval=${IntervalSec}s duration=${DurationSec}s (Ctrl+C to stop)" -ForegroundColor Yellow
    $all = @()
    $t0 = Get-Date
    $csv = Join-Path $OutputDir "memory_timeline.csv"
    "timestamp,heapUsedMB,heapCapacityMB,externalMB,vmRSS_MB,workingSetMB,privateMemoryMB" | Out-File $csv -Encoding utf8

    try {
        while ($true) {
            $el = ((Get-Date) - $t0).TotalSeconds
            if ($DurationSec -gt 0 -and $el -ge $DurationSec) {
                Write-Host "`n[mem_debug] Duration reached (${DurationSec}s)" -ForegroundColor Yellow
                break
            }
            $snap = Collect-MemorySnapshot -ShowTopClasses $false
            if ($snap) {
                $all += $snap
                $iso = if ($snap.isolates.Count -gt 0) { $snap.isolates[0] } else { $null }
                $pm = $snap.processMemory
                $line = "$($snap.timestamp),$($iso.heapUsedMB),$($iso.heapCapacityMB),$($iso.externalMB),$($snap.vm.currentRSS_MB),$($pm.WorkingSet64MB),$($pm.PrivateMemoryMB)"
                $line | Out-File $csv -Append -Encoding utf8
            }
            Start-Sleep -Seconds $IntervalSec
        }
    }
    catch { Write-Host "`n[mem_debug] Stopped" -ForegroundColor Yellow }

    $rf = Join-Path $OutputDir "memory_timeline_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $all | ConvertTo-Json -Depth 10 | Out-File $rf -Encoding utf8
    Write-Host "`n[mem_debug] Snapshots: $($all.Count)" -ForegroundColor Green
    Write-Host "[mem_debug] CSV: $csv" -ForegroundColor Green
    Write-Host "[mem_debug] JSON: $rf" -ForegroundColor Green

    if ($all.Count -gt 0) {
        $hv = $all | ForEach-Object { if ($_.isolates.Count -gt 0) { $_.isolates[0].heapUsedMB } } | Where-Object { $_ -ne $null }
        $rv = $all | ForEach-Object { $_.vm.currentRSS_MB } | Where-Object { $_ -ne $null }
        Write-Host "`n===== Summary =====" -ForegroundColor Cyan
        if ($hv.Count -gt 0) {
            Write-Host "  Dart Heap: min=$( ($hv|Measure-Object -Min).Minimum ) max=$( ($hv|Measure-Object -Max).Maximum ) avg=$( [math]::Round(($hv|Measure-Object -Avg).Average,2) ) MB" -ForegroundColor White
        }
        if ($rv.Count -gt 0) {
            Write-Host "  VM RSS:    min=$( ($rv|Measure-Object -Min).Minimum ) max=$( ($rv|Measure-Object -Max).Maximum ) avg=$( [math]::Round(($rv|Measure-Object -Avg).Average,2) ) MB" -ForegroundColor White
        }
        if ($hv.Count -ge 3) {
            $n = [math]::Ceiling($hv.Count / 3)
            $f = ($hv | Select-Object -First $n | Measure-Object -Avg).Average
            $l = ($hv | Select-Object -Last $n | Measure-Object -Avg).Average
            $g = [math]::Round($l - $f, 2)
            $gp = if ($f -gt 0) { [math]::Round(($g / $f) * 100, 1) } else { 0 }
            if ($gp -gt 20) { Write-Host "  [!] Possible leak: heap grew $g MB ($gp%)" -ForegroundColor Red }
            elseif ($gp -gt 5) { Write-Host "  [~] Heap slightly grew: $g MB ($gp%)" -ForegroundColor Yellow }
            else { Write-Host "  [OK] Heap stable: delta $g MB ($gp%)" -ForegroundColor Green }
        }
    }
} else {
    $snap = Collect-MemorySnapshot -ShowTopClasses $true
    if ($snap) {
        $rf = Join-Path $OutputDir "memory_snapshot_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $snap | ConvertTo-Json -Depth 10 | Out-File $rf -Encoding utf8
        Write-Host "`n[mem_debug] Report saved: $rf" -ForegroundColor Green
    }
}
