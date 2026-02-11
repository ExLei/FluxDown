<#
.SYNOPSIS
    FluxDown 内存调试 - 停止调试会话
.DESCRIPTION
    终止 flutter run 进程并清理 PID 文件。
    保留所有内存报告文件供后续分析。
#>

$ErrorActionPreference = "SilentlyContinue"
$OutputDir = Join-Path (Join-Path $PSScriptRoot "..") ".mem_debug"
$PidFile = Join-Path $OutputDir "flutter.pid"

if (Test-Path $PidFile) {
    $flutterPid = ((Get-Content $PidFile -Raw) -replace '[\r\n]', '').Trim()
    
    try {
        $proc = Get-Process -Id $flutterPid -ErrorAction Stop
        Write-Host "[mem_debug] 正在终止 Flutter 进程 (PID: $flutterPid)..." -ForegroundColor Yellow
        
        # 先尝试优雅关闭
        Stop-Process -Id $flutterPid -Force
        Start-Sleep -Seconds 2
        
        # 确认已终止
        $check = Get-Process -Id $flutterPid -ErrorAction SilentlyContinue
        if ($check) {
            Write-Host "[mem_debug] 进程未响应，强制终止..." -ForegroundColor Red
            Stop-Process -Id $flutterPid -Force
        }
        
        Write-Host "[mem_debug] Flutter 进程已终止" -ForegroundColor Green
    }
    catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        Write-Host "[mem_debug] 进程 $flutterPid 已不存在" -ForegroundColor Gray
    }
    
    Remove-Item $PidFile -Force
} else {
    Write-Host "[mem_debug] 未找到运行中的 Flutter 进程" -ForegroundColor Gray
}

# 列出保留的报告文件
Write-Host ""
Write-Host "[mem_debug] 保留的调试文件:" -ForegroundColor Cyan
if (Test-Path $OutputDir) {
    Get-ChildItem $OutputDir -File | ForEach-Object {
        $sizeMB = [math]::Round($_.Length / 1KB, 1)
        Write-Host "  $($_.Name)  ($sizeMB KB)" -ForegroundColor White
    }
    Write-Host ""
    Write-Host "[mem_debug] 清理所有调试文件: Remove-Item -Recurse .mem_debug" -ForegroundColor Gray
}
